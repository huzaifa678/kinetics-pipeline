"""Write a randomly-initialized CNN-LSTM artifact for LOCAL pipeline testing.

Produces ``model.pth`` + ``model_config.json`` + ``label_map.json`` in ``--out``
so the FastAPI backend can load and serve (meaningless) predictions. That's
enough to exercise the API, Prometheus metrics, and OTLP traces locally without
training a real model. Predictions are garbage by construction — this verifies
the *pipeline*, not the model.

Usage (from the training/ dir):
    python local/make_dummy_model.py --out local/model --num-classes 10
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import torch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from kinetics_trainer.model import CNNLSTM

# CNNLSTM constructor defaults (kept in sync with model.py) — also written into
# model_config.json so Predictor.from_model_dir rebuilds an identical architecture.
HIDDEN_SIZE = 512
LSTM_LAYERS = 2
BIDIRECTIONAL = True
CLIP_LENGTH = 16
FRAME_SIZE = 224


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="local/model", help="output artifact directory")
    ap.add_argument("--num-classes", type=int, default=10)
    ap.add_argument("--backbone", default="resnet18", help="small backbone keeps it fast")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    model = CNNLSTM(
        num_classes=args.num_classes,
        backbone=args.backbone,
        pretrained=False,
        hidden_size=HIDDEN_SIZE,
        lstm_layers=LSTM_LAYERS,
        bidirectional=BIDIRECTIONAL,
    )
    torch.save(model.state_dict(), os.path.join(args.out, "model.pth"))

    cfg = {
        "model": "cnn_lstm",
        "backbone": args.backbone,
        "num_classes": args.num_classes,
        "hidden_size": HIDDEN_SIZE,
        "lstm_layers": LSTM_LAYERS,
        "bidirectional": BIDIRECTIONAL,
        "clip_length": CLIP_LENGTH,
        "frame_size": FRAME_SIZE,
    }
    with open(os.path.join(args.out, "model_config.json"), "w") as f:
        json.dump(cfg, f, indent=2)

    label_map = {f"class_{i:03d}": i for i in range(args.num_classes)}
    with open(os.path.join(args.out, "label_map.json"), "w") as f:
        json.dump(label_map, f, indent=2)

    print(
        f"wrote dummy artifact to {args.out}/ "
        f"(model.pth, model_config.json, label_map.json; {args.num_classes} classes)"
    )


if __name__ == "__main__":
    main()
