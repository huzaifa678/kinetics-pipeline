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
    # data source: "manifest" decodes mp4s per epoch; "shards" streams pre-decoded
    # WebDataset tars from kinetics_trainer.etl (train_manifest still supplies the
    # label map, whose ordering the shard cls indices match). Defaulted so existing
    # construction sites and Config.for_inference are unaffected.
    data_format: str = "manifest"
    train_shards: str = ""
    val_shards: str = ""
    # Total training samples per epoch across all ranks. >0 enables the DDP-safe
    # shard path (resampled + with_epoch): each rank does epoch_size/world_size
    # samples, so uneven shard counts never desync ranks. 0 = single pass (1 node).
    shard_epoch_size: int = 0
    # LR scaling for the global (multi-rank) batch. Global batch = batch_size *
    # world_size, so the LR usually should grow with it: "linear" (lr * world_size,
    # large-batch SGD rule), "sqrt" (gentler, often better for Adam), "none".
    lr_scaling: str = "none"

    @classmethod
    def for_inference(cls, model_cfg: dict) -> Config:
        """Rebuild a Config from a saved model_config.json, for model reconstruction.

        Only the architecture fields matter at inference time; everything else gets
        harmless defaults. ``pretrained`` is forced False — weights come from the
        saved checkpoint, not a fresh download. Lets ModelFactory rebuild *any*
        registered model (cnn_lstm / r2plus1d / videomae) from its config alone.
        """
        return cls(
            model=model_cfg["model"],
            backbone=model_cfg.get("backbone", "resnet50"),
            pretrained=False,
            freeze_backbone_epochs=0,
            num_classes=model_cfg["num_classes"],
            hidden_size=model_cfg.get("hidden_size", 512),
            lstm_layers=model_cfg.get("lstm_layers", 2),
            bidirectional=model_cfg.get("bidirectional", True),
            clip_length=model_cfg.get("clip_length", 16),
            frame_size=model_cfg.get("frame_size", 224),
            train_manifest="",
            val_manifest="",
            num_workers=0,
            batch_size=1,
            epochs=0,
            lr=0.0,
            backbone_lr_mult=1.0,
            weight_decay=0.0,
            warmup_epochs=0,
            amp="no",
            torch_compile=False,
            seed=0,
            mlflow_tracking_uri="",
            experiment_name="",
            run_name="",
            checkpoint_s3="",
            checkpoint_every_steps=0,
            resume=False,
            output_dir="",
            log_every=0,
        )


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
    # Pre-decoded WebDataset shards (kinetics_trainer.etl). data-format=shards reads
    # these instead of decoding mp4s; brace patterns or pipe: URLs, e.g.
    # "pipe:aws s3 cp s3://bucket/train/clips-{00000..00063}.tar -".
    p.add_argument("--data-format", default="manifest", choices=["manifest", "shards"])
    p.add_argument("--train-shards", default="")
    p.add_argument("--val-shards", default="")
    p.add_argument("--shard-epoch-size", type=int, default=0, help="total train samples/epoch")

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
    p.add_argument("--lr-scaling", default="none", choices=["none", "linear", "sqrt"])
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
        data_format=a.data_format,
        train_shards=a.train_shards,
        val_shards=a.val_shards,
        shard_epoch_size=a.shard_epoch_size,
        batch_size=a.batch_size,
        epochs=a.epochs,
        lr=a.lr,
        backbone_lr_mult=a.backbone_lr_mult,
        lr_scaling=a.lr_scaling,
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
