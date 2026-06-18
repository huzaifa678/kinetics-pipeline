"""Edge-side predictor that delegates the forward-pass to a Seldon model.

The FastAPI app keeps doing request handling, video decode, metrics and tracing,
but instead of running the CNN-LSTM in-process it calls a Seldon Core v2 model
over the Open Inference (V2) protocol. This is what makes the serving backend an
*edge*: Seldon owns the model versions + A/B routing, the edge owns the HTTP
surface and rolls out independently (Argo Rollouts).

Structurally satisfies :class:`kinetics_trainer.predictor.PredictorLike`, so the
app holds it interchangeably with the local ``Predictor``.

Configured purely from env (set by the helm chart), so swapping local<->remote is
a deployment concern, not a code change:

* ``SELDON_ENDPOINT``       — base URL of the Seldon mesh, e.g.
  ``http://seldon-mesh.seldon-mesh`` (presence of this selects the remote path).
* ``SELDON_MODEL``          — model/experiment name to route to (default ``kinetics-cnn-lstm``).
* ``SELDON_TIMEOUT_SECONDS``— request timeout (default 30).
* ``CLIP_LENGTH`` / ``FRAME_SIZE`` — video-decode params (default 16 / 224).
"""

from __future__ import annotations

import json
import os

import httpx
import torch

from ..observability import get_logger
from ..predictor import Prediction, decode_video_bytes

log = get_logger("kinetics_remote_predictor")

DEFAULT_MODEL = "kinetics-cnn-lstm"
DEFAULT_TIMEOUT = 30.0


class RemotePredictor:
    """Calls a Seldon Core v2 model over the V2 inference protocol."""

    def __init__(
        self,
        endpoint: str,
        model_name: str = DEFAULT_MODEL,
        timeout: float = DEFAULT_TIMEOUT,
        clip_length: int = 16,
        frame_size: int = 224,
    ) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._model_name = model_name
        self._timeout = timeout
        self._clip_length = clip_length
        self._frame_size = frame_size
        self._client = httpx.Client(timeout=timeout)
        log.info("RemotePredictor -> %s (model=%s)", self._endpoint, model_name)

    @classmethod
    def from_env(cls, endpoint: str) -> RemotePredictor:
        """Build from the SELDON_*/CLIP_LENGTH/FRAME_SIZE env vars."""
        return cls(
            endpoint=endpoint,
            model_name=os.environ.get("SELDON_MODEL", DEFAULT_MODEL),
            timeout=float(os.environ.get("SELDON_TIMEOUT_SECONDS", DEFAULT_TIMEOUT)),
            clip_length=int(os.environ.get("CLIP_LENGTH", 16)),
            frame_size=int(os.environ.get("FRAME_SIZE", 224)),
        )

    @property
    def cfg(self) -> dict:
        """Minimal config surface — the real architecture lives in Seldon."""
        return {"model": self._model_name, "backbone": "remote"}

    @property
    def num_classes(self) -> int:
        """Unknown at the edge (the model is remote); reported as 0."""
        return 0

    def preprocess_video_bytes(self, raw: bytes) -> torch.Tensor:
        """Decode mp4 bytes to a clip tensor (same path as the local Predictor)."""
        return decode_video_bytes(raw, self._clip_length, self._frame_size)

    def predict(self, clip: torch.Tensor, top_k: int = 5) -> list[Prediction]:
        """POST the clip to the Seldon model and parse the top-k predictions."""
        payload = {
            "inputs": [
                {
                    "name": "clip",
                    "shape": list(clip.shape),
                    "datatype": "FP32",
                    "data": clip.flatten().tolist(),
                }
            ],
            "parameters": {"top_k": int(top_k)},
        }
        url = f"{self._endpoint}/v2/models/{self._model_name}/infer"
        resp = self._client.post(url, json=payload, headers={"Seldon-Model": self._model_name})
        resp.raise_for_status()
        body = resp.json()["outputs"][0]["data"][0]
        return [Prediction(label=p["label"], score=p["score"]) for p in json.loads(body)]
