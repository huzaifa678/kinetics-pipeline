"""Backend-agnostic inference for the CNN-LSTM action recognizer.

A single :class:`Predictor` owns model loading and prediction so every serving
surface shares one code path instead of duplicating it:

* the SageMaker handler (``inference/inference.py``), and
* the FastAPI app (``kinetics_trainer.serving.app``).

The artifact directory must contain ``model.pth`` (state_dict),
``model_config.json`` (architecture, from ``kinetics_trainer.model``) and
``label_map.json`` (``{class_name: index}``).
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Protocol

import torch

from .config import Config
from .model import ModelFactory
from .observability import get_logger

log = get_logger("kinetics_predictor")


@dataclass(frozen=True)
class Prediction:
    """A single top-k entry."""

    label: str
    score: float


class PredictorLike(Protocol):
    """Structural interface shared by the local Predictor and the edge RemotePredictor.

    Lets the FastAPI app hold either backend behind one type: a local in-process
    model, or a remote one that delegates the forward-pass to a Seldon endpoint.
    """

    @property
    def cfg(self) -> dict: ...

    @property
    def num_classes(self) -> int: ...

    def preprocess_video_bytes(self, raw: bytes) -> torch.Tensor: ...

    def predict(self, clip: torch.Tensor, top_k: int = 5) -> list[Prediction]: ...


def decode_video_bytes(raw: bytes, clip_length: int = 16, frame_size: int = 224) -> torch.Tensor:
    """Decode raw mp4 bytes into a normalized ``(T, 3, H, W)`` clip tensor.

    Shared by the local :class:`Predictor` and the edge ``RemotePredictor`` so the
    video-preprocessing path is identical regardless of where the model runs.
    """
    import tempfile

    from .data import build_transform, decode_clip

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as fh:
        fh.write(raw)
        path = fh.name
    try:
        frames = decode_clip(path, clip_length)
    finally:
        os.unlink(path)
    tf = build_transform(frame_size, train=False)
    return torch.stack([tf(f) for f in frames], dim=0)


class Predictor:
    """Loads any registered trained model artifact and runs top-k inference."""

    def __init__(
        self,
        model: torch.nn.Module,
        idx_to_label: dict[int, str],
        cfg: dict,
        device: str,
    ) -> None:
        self._model = model
        self._idx_to_label = idx_to_label
        self._cfg = cfg
        self._device = device

    @property
    def cfg(self) -> dict:
        return self._cfg

    @property
    def device(self) -> str:
        return self._device

    @property
    def num_classes(self) -> int:
        return len(self._idx_to_label)

    @classmethod
    def from_model_dir(cls, model_dir: str) -> Predictor:
        """Build a predictor from a model artifact directory.

        Rebuilds *any* registered model (cnn_lstm / r2plus1d / videomae) via the
        ModelFactory from the saved model_config.json, so the serving path tracks
        the training registry — no per-architecture branching here.
        """
        with open(os.path.join(model_dir, "model_config.json")) as f:
            cfg = json.load(f)
        with open(os.path.join(model_dir, "label_map.json")) as f:
            label_map = json.load(f)

        # Rebuild the model architecture from the config, then load the state dict.
        model = ModelFactory.create(Config.for_inference(cfg))
        state = torch.load(os.path.join(model_dir, "model.pth"), map_location="cpu")
        model.load_state_dict(state)
        model.eval()
        device = "cuda" if torch.cuda.is_available() else "cpu"
        model.to(device)

        idx_to_label = {v: k for k, v in label_map.items()}
        log.info(
            "loaded model (%s/%s) on %s, %d classes",
            cfg.get("model"),
            cfg.get("backbone"),
            device,
            len(idx_to_label),
        )
        return cls(model, idx_to_label, cfg, device)

    def preprocess_video_bytes(self, raw: bytes) -> torch.Tensor:
        """Decode raw mp4 bytes into a normalized ``(T, 3, H, W)`` clip tensor."""
        return decode_video_bytes(
            raw,
            clip_length=int(self._cfg.get("clip_length", 16)),
            frame_size=int(self._cfg.get("frame_size", 224)),
        )

    @torch.no_grad()
    def predict(self, clip: torch.Tensor, top_k: int = 5) -> list[Prediction]:
        """Run inference on a ``(T, 3, H, W)`` or ``(B, T, 3, H, W)`` clip."""
        if clip.dim() == 4:  # (T,3,H,W) -> add batch dim
            clip = clip.unsqueeze(0)
        clip = clip.to(self._device)
        probs = torch.softmax(self._model(clip), dim=1)[0]
        k = min(top_k, probs.numel())
        topk = torch.topk(probs, k=k)
        return [
            Prediction(label=self._idx_to_label[int(i)], score=float(s))
            for s, i in zip(topk.values, topk.indices, strict=True)
        ]
