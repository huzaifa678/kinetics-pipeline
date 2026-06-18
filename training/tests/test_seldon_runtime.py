"""Smoke tests for the Seldon Core v2 custom MLServer runtime.

Skipped unless mlserver + torch + numpy are importable, so they don't break the
minimal smoke-test env. The Predictor is replaced with an injected fake, so no
real artifact / model is needed. Run: python -m pytest training/tests/test_seldon_runtime.py
"""

import asyncio
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

pytest.importorskip("mlserver")
pytest.importorskip("torch")
pytest.importorskip("numpy")

import numpy as np
from mlserver.codecs import NumpyRequestCodec, StringCodec
from mlserver.settings import ModelParameters, ModelSettings
from mlserver.types import Parameters

import kinetics_trainer.serving.seldon_runtime as rt
from kinetics_trainer.predictor import Prediction


class _FakePredictor:
    num_classes = 2

    def predict(self, clip, top_k=5):
        return [Prediction("dancing", 0.9), Prediction("running", 0.1)][:top_k]


@pytest.fixture()
def runtime(monkeypatch):
    monkeypatch.setattr(
        rt.Predictor, "from_model_dir", classmethod(lambda cls, d: _FakePredictor())
    )
    settings = ModelSettings(
        name="kinetics",
        implementation=rt.KineticsRuntime,
        parameters=ModelParameters(uri="/tmp/fake-artifact"),
    )
    r = rt.KineticsRuntime(settings)
    assert asyncio.run(r.load()) is True
    return r


def _clip_request():
    return NumpyRequestCodec.encode_request(np.zeros((16, 3, 224, 224), dtype=np.float32))


def test_predict_returns_topk(runtime):
    resp = asyncio.run(runtime.predict(_clip_request()))
    body = StringCodec.decode_output(resp.outputs[0])[0]
    preds = json.loads(body)
    assert preds[0]["label"] == "dancing"
    assert preds[0]["score"] == pytest.approx(0.9)


def test_top_k_param_respected(runtime):
    req = _clip_request()
    req.parameters = Parameters(top_k=1)
    resp = asyncio.run(runtime.predict(req))
    preds = json.loads(StringCodec.decode_output(resp.outputs[0])[0])
    assert len(preds) == 1


def test_load_requires_uri(monkeypatch):
    monkeypatch.setattr(
        rt.Predictor, "from_model_dir", classmethod(lambda cls, d: _FakePredictor())
    )
    r = rt.KineticsRuntime(ModelSettings(name="k", implementation=rt.KineticsRuntime))
    with pytest.raises(ValueError, match=r"parameters\.uri"):
        asyncio.run(r.load())


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
