"""FastAPI inference backend for the CNN-LSTM action recognizer.

A self-hosted serving surface (complementing the SageMaker handler) meant to run
as a Deployment on the existing EKS cluster and be scraped by
kube-prometheus-stack via a ServiceMonitor on ``/metrics``.

Endpoints
---------
* ``POST /predict`` — top-k action prediction from a clip tensor or mp4 bytes.
* ``GET /healthz``  — liveness (process up).
* ``GET /readyz``   — readiness (model loaded; 503 until then).
* ``GET /metrics``  — Prometheus exposition.

Config via env
--------------
* ``MODEL_DIR`` — dir with ``model.pth`` + ``model_config.json`` + ``label_map.json``
  (default ``/opt/ml/model``).
* ``OTEL_EXPORTER_OTLP_ENDPOINT`` / ``OTEL_SERVICE_NAME`` — optional tracing; the
  tracer no-ops when the endpoint is unset.

Run locally::

    uvicorn kinetics_trainer.serving.app:app --host 0.0.0.0 --port 8080
"""

from __future__ import annotations

import base64
import os
import time
from contextlib import asynccontextmanager

import torch
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from ..observability import get_logger, init_tracer
from ..predictor import Predictor, PredictorLike
from . import metrics
from .remote_predictor import RemotePredictor
from .schemas import HealthResponse, PredictRequest, PredictResponse

log = get_logger("kinetics_serving")

# Holds the singleton predictor, populated at startup by the lifespan handler.
_state: dict[str, PredictorLike | None] = {"predictor": None}


@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: ANN201 (FastAPI lifespan signature)
    """Load the model once at startup; release it on shutdown.

    Picks the backend from env: if SELDON_ENDPOINT is set, the app runs as an
    *edge* and delegates the forward-pass to a Seldon model; otherwise it loads
    the model in-process from MODEL_DIR (unchanged local behaviour).
    """
    init_tracer(service_name=os.environ.get("OTEL_SERVICE_NAME", "kinetics-inference"))
    seldon_endpoint = os.environ.get("SELDON_ENDPOINT", "")
    if seldon_endpoint:
        log.info("serving via Seldon endpoint %s", seldon_endpoint)
        predictor: PredictorLike = RemotePredictor.from_env(seldon_endpoint)
    else:
        model_dir = os.environ.get("MODEL_DIR", "/opt/ml/model")
        log.info("loading model from %s", model_dir)
        predictor = Predictor.from_model_dir(model_dir)
    _state["predictor"] = predictor
    metrics.MODEL_INFO.labels(
        model=predictor.cfg.get("model", "unknown"),
        backbone=predictor.cfg.get("backbone", "unknown"),
        num_classes=str(predictor.num_classes),
    ).set(1)
    yield
    _state["predictor"] = None


app = FastAPI(title="Kinetics Inference API", version="1.0.0", lifespan=lifespan)


@app.get("/healthz", response_model=HealthResponse)
def healthz() -> HealthResponse:
    return HealthResponse(status="ok", model_loaded=_state["predictor"] is not None)


@app.get("/readyz", response_model=HealthResponse)
def readyz() -> HealthResponse:
    if _state["predictor"] is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    return HealthResponse(status="ready", model_loaded=True)


@app.get("/metrics")
def prometheus_metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest) -> PredictResponse:
    predictor = _state["predictor"]
    if predictor is None:
        raise HTTPException(status_code=503, detail="model not loaded")

    endpoint = "/predict"
    metrics.IN_PROGRESS.inc()
    start = time.perf_counter()
    try:
        if req.clip is not None:
            clip = torch.tensor(req.clip, dtype=torch.float32)
        else:
            clip = predictor.preprocess_video_bytes(base64.b64decode(req.video_b64))
        preds = predictor.predict(clip, top_k=req.top_k)
        if preds:
            metrics.record_prediction(preds[0].label, preds[0].score)
        metrics.REQUESTS.labels(endpoint=endpoint, status="ok").inc()
        return PredictResponse(predictions=[{"label": p.label, "score": p.score} for p in preds])
    except HTTPException:
        metrics.REQUESTS.labels(endpoint=endpoint, status="client_error").inc()
        raise
    except Exception as exc:
        metrics.REQUESTS.labels(endpoint=endpoint, status="error").inc()
        log.exception("prediction failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        metrics.LATENCY.labels(endpoint=endpoint).observe(time.perf_counter() - start)
        metrics.IN_PROGRESS.dec()
