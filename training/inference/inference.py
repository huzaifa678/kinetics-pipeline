"""SageMaker PyTorch inference handler for the CNN-LSTM action recognizer.

The endpoint serves the model trained on HyperPod. The model artifact
(model.tar.gz) must contain:
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
import tempfile

import torch

from src.kinetics_trainer.model import CNNLSTM
from src.kinetics_trainer.observability import get_logger, init_tracer

log = get_logger("kinetics_inference")


def _build_from_config(cfg: dict) -> torch.nn.Module:
    if cfg["model"] != "cnn_lstm":
        raise ValueError(f"inference handler supports cnn_lstm, got {cfg['model']}")
    return CNNLSTM(
        num_classes=cfg["num_classes"],
        backbone=cfg["backbone"],
        pretrained=False,
        hidden_size=cfg["hidden_size"],
        lstm_layers=cfg["lstm_layers"],
        bidirectional=cfg["bidirectional"],
    )


def model_fn(model_dir: str) -> dict:
    with open(os.path.join(model_dir, "model_config.json")) as f:
        cfg = json.load(f)
    with open(os.path.join(model_dir, "label_map.json")) as f:
        label_map = json.load(f)
    idx_to_label = {v: k for k, v in label_map.items()}

    model = _build_from_config(cfg)
    state = torch.load(os.path.join(model_dir, "model.pth"), map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model.to(device)
    # No-op unless OTEL_EXPORTER_OTLP_ENDPOINT is set in the endpoint's env.
    init_tracer(service_name=os.environ.get("OTEL_SERVICE_NAME", "kinetics-inference"))
    log.info(
        "loaded model (%s/%s) on %s, %d classes",
        cfg.get("model"),
        cfg.get("backbone"),
        device,
        len(idx_to_label),
    )
    return {"model": model, "cfg": cfg, "idx_to_label": idx_to_label, "device": device}


def input_fn(request_body: str | bytes, content_type: str = "application/json") -> dict:
    if content_type != "application/json":
        raise ValueError(f"unsupported content type {content_type}")
    payload = json.loads(request_body)
    if "clip" in payload:
        return {"clip": torch.tensor(payload["clip"], dtype=torch.float32)}
    if "video_b64" in payload:
        from src.kinetics_trainer.data import build_transform, decode_clip

        cfg = payload.get("cfg", {})
        clip_len = int(cfg.get("clip_length", 16))
        frame_size = int(cfg.get("frame_size", 224))
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as fh:
            fh.write(base64.b64decode(payload["video_b64"]))
            path = fh.name
        frames = decode_clip(path, clip_len)
        os.unlink(path)
        tf = build_transform(frame_size, train=False)
        clip = torch.stack([tf(f) for f in frames], dim=0)
        return {"clip": clip}
    raise ValueError("request must contain 'clip' or 'video_b64'")


def predict_fn(data: dict, ctx: dict) -> list[dict]:
    from src.kinetics_trainer.observability import get_tracer

    model, device, idx_to_label = ctx["model"], ctx["device"], ctx["idx_to_label"]
    clip = data["clip"]
    if clip.dim() == 4:  # (T,3,H,W) -> add batch dim
        clip = clip.unsqueeze(0)
    with get_tracer().start_as_current_span("predict") as span:
        span.set_attribute("batch_size", int(clip.shape[0]))
        clip = clip.to(device)
        with torch.no_grad():
            probs = torch.softmax(model(clip), dim=1)[0]
        topk = torch.topk(probs, k=min(5, probs.numel()))
    return [
        {"label": idx_to_label[int(i)], "score": float(s)}
        for s, i in zip(topk.values, topk.indices, strict=True)
    ]


def output_fn(prediction: list[dict], accept: str = "application/json") -> tuple[str, str]:
    return json.dumps({"predictions": prediction}), "application/json"
