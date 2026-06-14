"""SageMaker PyTorch inference handler for the CNN-LSTM action recognizer.

Thin adapter over :class:`kinetics_trainer.predictor.Predictor` (the same core
the FastAPI app uses) implementing the SageMaker ``model_fn`` / ``input_fn`` /
``predict_fn`` / ``output_fn`` contract. The model artifact (model.tar.gz) must
contain:
    model.pth          - state_dict
    model_config.json  - architecture (from kinetics_trainer.model.model_config)
    label_map.json     - {class_name: index}

Request (application/json):
    {"clip": [[[...]]]}   # nested list shaped (T, 3, H, W), already normalized
  or
    {"video_b64": "..."}  # base64 mp4 bytes -> decoded + preprocessed server-side
"""

from __future__ import annotations

import base64
import json
import os

import torch

from src.kinetics_trainer.observability import init_tracer
from src.kinetics_trainer.predictor import Predictor


def model_fn(model_dir: str) -> dict:
    predictor = Predictor.from_model_dir(model_dir)
    # No-op unless OTEL_EXPORTER_OTLP_ENDPOINT is set in the endpoint's env.
    init_tracer(service_name=os.environ.get("OTEL_SERVICE_NAME", "kinetics-inference"))
    return {"predictor": predictor}


def input_fn(request_body: str | bytes, content_type: str = "application/json") -> dict:
    if content_type != "application/json":
        raise ValueError(f"unsupported content type {content_type}")
    payload = json.loads(request_body)
    if "clip" in payload:
        return {"clip": torch.tensor(payload["clip"], dtype=torch.float32)}
    if "video_b64" in payload:
        return {"video_b64": base64.b64decode(payload["video_b64"])}
    raise ValueError("request must contain 'clip' or 'video_b64'")


def predict_fn(data: dict, ctx: dict) -> list[dict]:
    predictor: Predictor = ctx["predictor"]
    if "video_b64" in data:
        clip = predictor.preprocess_video_bytes(data["video_b64"])
    else:
        clip = data["clip"]
    preds = predictor.predict(clip, top_k=5)
    return [{"label": p.label, "score": p.score} for p in preds]


def output_fn(prediction: list[dict], accept: str = "application/json") -> tuple[str, str]:
    return json.dumps({"predictions": prediction}), "application/json"
