"""Smoke tests for the FastAPI inference backend.

Skipped unless the serving extra + torch are importable, so they don't break the
minimal smoke-test env. The model is replaced with an injected fake, so no real
artifact / GPU / PyAV is needed. Run: python -m pytest training/tests/test_serving.py
"""

import os
import sys
from typing import ClassVar

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

pytest.importorskip("fastapi")
pytest.importorskip("torch")
pytest.importorskip("torchvision")
pytest.importorskip("prometheus_client")

from fastapi.testclient import TestClient

import kinetics_trainer.serving.app as app_module
from kinetics_trainer.predictor import Prediction


class _FakePredictor:
    cfg: ClassVar[dict] = {"model": "cnn_lstm", "backbone": "resnet18"}
    num_classes = 2

    def predict(self, clip, top_k=5):
        return [Prediction("dancing", 0.9), Prediction("running", 0.1)][:top_k]

    def preprocess_video_bytes(self, raw):
        raise AssertionError("video path not exercised in this test")


@pytest.fixture()
def client(monkeypatch):
    # Patch the loader so the app's lifespan injects the fake instead of reading S3.
    monkeypatch.setattr(
        app_module.Predictor,
        "from_model_dir",
        classmethod(lambda cls, model_dir: _FakePredictor()),
    )
    with TestClient(app_module.app) as c:
        yield c


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["model_loaded"] is True


def test_readyz(client):
    assert client.get("/readyz").status_code == 200


def test_predict_clip(client):
    r = client.post("/predict", json={"clip": [[[[0.0]]]], "top_k": 2})
    assert r.status_code == 200
    preds = r.json()["predictions"]
    assert preds[0]["label"] == "dancing"
    assert preds[0]["score"] == pytest.approx(0.9)


def test_metrics_exposition(client):
    client.post("/predict", json={"clip": [[[[0.0]]]], "top_k": 2})
    body = client.get("/metrics").text
    assert "inference_requests_total" in body
    assert "model_prediction_confidence" in body
    assert "model_info" in body


def test_predict_rejects_both_inputs(client):
    r = client.post("/predict", json={"clip": [[1]], "video_b64": "eA=="})
    assert r.status_code == 422  # pydantic: exactly one of clip/video_b64


def test_predict_rejects_neither_input(client):
    r = client.post("/predict", json={"top_k": 3})
    assert r.status_code == 422


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
