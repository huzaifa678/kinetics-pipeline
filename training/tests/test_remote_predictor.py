"""Smoke tests for the edge RemotePredictor (Seldon delegation).

Skipped unless httpx + torch are importable. The HTTP call is intercepted with an
httpx MockTransport, so no real Seldon endpoint is needed.
"""

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

pytest.importorskip("httpx")
pytest.importorskip("torch")

import httpx
import torch

import kinetics_trainer.serving.remote_predictor as rp


def _seldon_response(request: httpx.Request) -> httpx.Response:
    body = json.loads(request.content)
    # Echo back the requested top_k worth of predictions in V2 output shape.
    top_k = body["parameters"]["top_k"]
    preds = [{"label": "dancing", "score": 0.9}, {"label": "running", "score": 0.1}][:top_k]
    return httpx.Response(
        200, json={"outputs": [{"name": "predictions", "data": [json.dumps(preds)]}]}
    )


@pytest.fixture()
def predictor():
    p = rp.RemotePredictor(endpoint="http://seldon.test", model_name="kinetics")
    p._client = httpx.Client(transport=httpx.MockTransport(_seldon_response))
    return p


def test_predict_parses_v2_output(predictor):
    preds = predictor.predict(torch.zeros((16, 3, 224, 224)), top_k=2)
    assert preds[0].label == "dancing"
    assert preds[0].score == pytest.approx(0.9)
    assert len(preds) == 2


def test_predict_sends_v2_request(predictor):
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        captured["header"] = request.headers.get("Seldon-Model")
        captured["url"] = str(request.url)
        return _seldon_response(request)

    predictor._client = httpx.Client(transport=httpx.MockTransport(handler))
    predictor.predict(torch.zeros((16, 3, 224, 224)), top_k=1)

    assert captured["body"]["inputs"][0]["name"] == "clip"
    assert captured["body"]["inputs"][0]["shape"] == [16, 3, 224, 224]
    assert captured["body"]["inputs"][0]["datatype"] == "FP32"
    assert captured["header"] == "kinetics"
    assert captured["url"].endswith("/v2/models/kinetics/infer")


def test_from_env_reads_config(monkeypatch):
    monkeypatch.setenv("SELDON_MODEL", "kinetics-ab")
    monkeypatch.setenv("CLIP_LENGTH", "8")
    p = rp.RemotePredictor.from_env("http://seldon.test/")
    assert p._model_name == "kinetics-ab"
    assert p._clip_length == 8
    assert p._endpoint == "http://seldon.test"  # trailing slash stripped


def test_satisfies_predictor_protocol():
    from kinetics_trainer.predictor import PredictorLike

    p = rp.RemotePredictor(endpoint="http://seldon.test")
    assert isinstance(p, PredictorLike) or all(
        hasattr(p, m) for m in ("cfg", "num_classes", "preprocess_video_bytes", "predict")
    )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
