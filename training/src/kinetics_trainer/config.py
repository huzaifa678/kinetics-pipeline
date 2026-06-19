"""Command-line configuration.

Flags mirror the contract in helm/training-job/templates/hyperpod-pytorchjob.yaml
exactly.
"""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass


def str2bool(v: str | bool) -> bool:
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in {"1", "true", "yes", "y", "t"}


@dataclass
class Config:
    """Typed training configuration parsed from the CLI (see parse_args)."""

    # model
    model: str
    backbone: str
    pretrained: bool
    freeze_backbone_epochs: int
    num_classes: int
    hidden_size: int
    lstm_layers: int
    bidirectional: bool
    # data
    clip_length: int
    frame_size: int
    train_manifest: str
    val_manifest: str
    num_workers: int
    # optimization
    batch_size: int
    epochs: int
    lr: float
    backbone_lr_mult: float
    weight_decay: float
    warmup_epochs: int
    amp: str  # "no" | "fp16" | "bf16"
    torch_compile: bool
    seed: int
    # experiment tracking
    mlflow_tracking_uri: str
    experiment_name: str
    run_name: str
    # checkpointing
    checkpoint_s3: str
    checkpoint_every_steps: int
    resume: bool
    output_dir: str
    log_every: int


def parse_args(argv: list[str] | None = None) -> Config:
    p = argparse.ArgumentParser("kinetics-trainer")

    # model
    p.add_argument("--model", default="cnn_lstm", choices=["cnn_lstm", "r2plus1d", "videomae"])
    p.add_argument("--backbone", default="resnet50", choices=["resnet18", "resnet34", "resnet50"])
    p.add_argument("--pretrained", type=str2bool, default=True)
    p.add_argument("--freeze-backbone-epochs", type=int, default=3)
    p.add_argument("--num-classes", type=int, default=400)
    p.add_argument("--hidden-size", type=int, default=512)
    p.add_argument("--lstm-layers", type=int, default=2)
    p.add_argument("--bidirectional", type=str2bool, default=True)

    # data
    p.add_argument("--clip-length", type=int, default=16)
    p.add_argument("--frame-size", type=int, default=224)
    p.add_argument("--train-manifest", required=True)
    p.add_argument("--val-manifest", required=True)
    p.add_argument("--num-workers", type=int, default=8)

    # optimization
    p.add_argument("--batch-size", type=int, default=16)
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument(
        "--backbone-lr-mult",
        type=float,
        default=0.1,
        help="backbone LR = lr * this (discriminative fine-tuning)",
    )
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--warmup-epochs", type=int, default=2)
    p.add_argument("--amp", default="bf16", choices=["no", "fp16", "bf16"])
    p.add_argument("--torch-compile", type=str2bool, default=True)
    p.add_argument("--seed", type=int, default=42)

    # experiment tracking (MLflow; SageMaker-managed MLflow ARN also works)
    p.add_argument("--mlflow-tracking-uri", default=os.environ.get("MLFLOW_TRACKING_URI", ""))
    p.add_argument("--experiment-name", default="kinetics-cnn-lstm")
    p.add_argument("--run-name", default=os.environ.get("RUN_NAME", ""))

    # checkpointing
    p.add_argument("--checkpoint-s3", default="", help="s3://bucket/prefix/ for checkpoints")
    p.add_argument("--checkpoint-every-steps", type=int, default=200)
    p.add_argument("--resume", type=str2bool, default=True)
    p.add_argument("--output-dir", default="/tmp/kinetics-output")
    p.add_argument("--log-every", type=int, default=20)

    a = p.parse_args(argv)
    return Config(
        model=a.model,
        backbone=a.backbone,
        pretrained=a.pretrained,
        freeze_backbone_epochs=a.freeze_backbone_epochs,
        num_classes=a.num_classes,
        hidden_size=a.hidden_size,
        lstm_layers=a.lstm_layers,
        bidirectional=a.bidirectional,
        clip_length=a.clip_length,
        frame_size=a.frame_size,
        train_manifest=a.train_manifest,
        val_manifest=a.val_manifest,
        num_workers=a.num_workers,
        batch_size=a.batch_size,
        epochs=a.epochs,
        lr=a.lr,
        backbone_lr_mult=a.backbone_lr_mult,
        weight_decay=a.weight_decay,
        warmup_epochs=a.warmup_epochs,
        amp=a.amp,
        torch_compile=a.torch_compile,
        seed=a.seed,
        mlflow_tracking_uri=a.mlflow_tracking_uri,
        experiment_name=a.experiment_name,
        run_name=a.run_name,
        checkpoint_s3=a.checkpoint_s3,
        checkpoint_every_steps=a.checkpoint_every_steps,
        resume=a.resume,
        output_dir=a.output_dir,
        log_every=a.log_every,
    )
