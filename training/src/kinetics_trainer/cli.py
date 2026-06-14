"""Entry point + composition root.

`torchrun --nproc_per_node=N train.py [flags]` calls main(). This module owns two
things only: the process-group lifecycle and wiring concrete collaborators
together to inject into the Trainer.
"""

from __future__ import annotations

import os
import random

import numpy as np
import torch

from .checkpoint import CheckpointManager, NullStorage, S3Storage
from .config import Config, parse_args
from .data import KineticsDataModule
from .distributed import DistContext, distributed_context
from .model import ModelFactory
from .observability import get_logger, init_tracer, shutdown_tracer
from .tracking import build_tracker
from .trainer import Trainer

log = get_logger(__name__)


def _seed_everything(seed: int, rank: int) -> None:
    s = seed + rank
    random.seed(s)
    np.random.seed(s)
    torch.manual_seed(s)
    torch.cuda.manual_seed_all(s)


def _run(cfg: Config, ctx: DistContext) -> None:
    _seed_everything(cfg.seed, ctx.rank)
    torch.backends.cudnn.benchmark = True
    os.makedirs(cfg.output_dir, exist_ok=True)

    tracer = init_tracer(
        service_name=os.environ.get("OTEL_SERVICE_NAME", "kinetics-trainer"),
        resource_attributes={
            "kinetics.rank": ctx.rank,
            "kinetics.world_size": ctx.world_size,
            "kinetics.model": cfg.model,
        },
    )
    log.info(
        "world_size=%d device=%s model=%s rank=%d", ctx.world_size, ctx.device, cfg.model, ctx.rank
    )

    model = ModelFactory.create(cfg).to(ctx.device)
    datamodule = KineticsDataModule(cfg, ctx)
    storage = S3Storage() if cfg.checkpoint_s3 else NullStorage()
    checkpointer = CheckpointManager(
        cfg.output_dir, cfg.checkpoint_s3, storage=storage, is_main=ctx.is_main
    )
    tracker = build_tracker(cfg, enabled=ctx.is_main)

    trainer = Trainer(cfg, ctx, model, datamodule, checkpointer, tracker, tracer)
    try:
        trainer.setup()
        trainer.fit()
    finally:
        tracker.end()
        shutdown_tracer()  # flush buffered spans before exit


def main(argv: list[str] | None = None) -> None:
    """Run training, owning the process-group lifecycle.

    distributed_context guarantees teardown even if training raises, so a crash on
    one rank can't leave the others hanging forever in a NCCL collective.
    """
    cfg: Config = parse_args(argv)
    with distributed_context() as ctx:
        _run(cfg, ctx)


if __name__ == "__main__":
    main()
