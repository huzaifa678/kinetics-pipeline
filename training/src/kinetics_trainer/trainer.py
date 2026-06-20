"""Trainer — orchestrates the fit/evaluate loop.

This is the composition target of the package: it depends on injected
collaborators (a DataModule, a CheckpointManager, an ExperimentTracker, the
DistContext and a tracer) rather than constructing them, so each can be swapped
or faked independently (DI + DIP). It owns only training policy — the
warmup/unfreeze schedule, optimizer (re)building, AMP, resume and the epoch
loop; persistence, data wiring and experiment logging live behind their seams.
"""

from __future__ import annotations

import os
import time
from dataclasses import asdict
from typing import Any

import torch
import torch.nn as nn
from torch.nn.parallel import DistributedDataParallel as DDP

from .checkpoint import CheckpointManager
from .config import Config
from .data import KineticsDataModule, save_label_map
from .distributed import DistContext, all_reduce_mean, barrier, scaled_lr
from .engine import AMP_DTYPE, accuracy
from .model import build_param_groups, model_config
from .observability import get_logger
from .tracking import ExperimentTracker

log = get_logger(__name__)


class Trainer:
    """Orchestrates the fit/evaluate loop over its injected collaborators."""

    def __init__(
        self,
        cfg: Config,
        ctx: DistContext,
        model: nn.Module,
        datamodule: KineticsDataModule,
        checkpointer: CheckpointManager,
        tracker: ExperimentTracker,
        tracer: Any,
    ) -> None:
        self.cfg = cfg
        self.ctx = ctx
        self.datamodule = datamodule
        self.checkpointer = checkpointer
        self.tracker = tracker
        self.tracer = tracer

        # Backbone warmup (freeze then unfreeze) only applies to cnn_lstm.
        self.use_warmup = cfg.model == "cnn_lstm" and cfg.freeze_backbone_epochs > 0
        self.model = self._wrap(model)
        self.scaler = torch.cuda.amp.GradScaler(enabled=cfg.amp == "fp16")
        self.optimizer: torch.optim.Optimizer | None = None
        self.scheduler: torch.optim.lr_scheduler._LRScheduler | None = None
        self.start_epoch = 0
        self.global_step = 0

    # ----- model wrapping helpers -----
    def _wrap(self, model: nn.Module) -> nn.Module:
        cfg, ctx = self.cfg, self.ctx
        wrapped = (
            torch.compile(model) if (cfg.torch_compile and hasattr(torch, "compile")) else model
        )
        if ctx.distributed:
            wrapped = DDP(
                wrapped, device_ids=[ctx.local_rank] if ctx.device.type == "cuda" else None
            )
        return wrapped

    def _unwrap(self) -> nn.Module:
        m = self.model.module if isinstance(self.model, DDP) else self.model
        return getattr(m, "_orig_mod", m)  # peel torch.compile wrapper too

    def _build_optim_sched(
        self, epoch: int
    ) -> tuple[torch.optim.Optimizer, torch.optim.lr_scheduler.LRScheduler]:
        """(Re)build optimizer + scheduler from the params that currently require grad.

        Called at start and again when the backbone unfreezes.
        """
        cfg = self.cfg
        lr = scaled_lr(cfg.lr, cfg.lr_scaling, self.ctx.world_size)
        if lr != cfg.lr:
            log.info(
                "scaled LR %.2e -> %.2e (%s, world_size=%d)",
                cfg.lr,
                lr,
                cfg.lr_scaling,
                self.ctx.world_size,
            )
        optimizer = torch.optim.AdamW(
            build_param_groups(self._unwrap(), lr, cfg.backbone_lr_mult),
            weight_decay=cfg.weight_decay,
        )
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=cfg.epochs)
        scheduler.last_epoch = epoch - 1
        return optimizer, scheduler

    # ----- lifecycle -----
    def setup(self) -> Trainer:
        cfg, ctx = self.cfg, self.ctx
        with self.tracer.start_as_current_span("setup"):
            self.datamodule.setup()
            if ctx.is_main:
                save_label_map(
                    self.datamodule.label_map, os.path.join(cfg.output_dir, "label_map.json")
                )

        self.tracker.log_params(asdict(cfg))
        self.tracker.set_tags(
            {"dataset_hash": self.datamodule.data_hash, "world_size": ctx.world_size}
        )

        # resume (HyperPod auto-resume after a fault), then build optim
        state = self.checkpointer.load_latest(map_location=ctx.device) if cfg.resume else None
        if state is not None:
            self._unwrap().load_state_dict(state["model"])
            self.start_epoch = state["epoch"] + 1
            self.global_step = state.get("global_step", 0)
            if ctx.is_main:
                log.info("resumed from epoch %d (step %d)", self.start_epoch, self.global_step)

        backbone_trainable = (not self.use_warmup) or (
            self.start_epoch >= cfg.freeze_backbone_epochs
        )
        if cfg.model == "cnn_lstm":
            self._unwrap().set_backbone_trainable(backbone_trainable)

        self.optimizer, self.scheduler = self._build_optim_sched(self.start_epoch)
        if state is not None:
            try:
                self.optimizer.load_state_dict(state["optimizer"])
                self.scheduler.load_state_dict(state["scheduler"])
                if state.get("scaler"):
                    self.scaler.load_state_dict(state["scaler"])
            except (ValueError, KeyError) as e:  # param groups changed across resume
                if ctx.is_main:
                    log.warning("optimizer state not restored (%s); continuing fresh", e)
        barrier()
        return self

    def _state(self, epoch: int, step: int) -> dict:
        return {
            "model": self._unwrap().state_dict(),
            "optimizer": self.optimizer.state_dict(),
            "scheduler": self.scheduler.state_dict(),
            "scaler": self.scaler.state_dict() if self.cfg.amp == "fp16" else None,
            "epoch": epoch,
            "global_step": step,
            "config": model_config(self.cfg),
            "dataset_hash": self.datamodule.data_hash,
        }

    def _save_checkpoint(self, epoch: int, step: int) -> None:
        self.checkpointer.save(self._state(epoch, step))

    # ----- loops -----
    def _train_epoch(self, epoch: int) -> None:
        cfg, ctx = self.cfg, self.ctx
        self.model.train()
        criterion = nn.CrossEntropyLoss()
        use_amp = cfg.amp != "no" and ctx.device.type == "cuda"
        amp_dtype = AMP_DTYPE.get(cfg.amp, torch.bfloat16)
        t0 = time.time()

        for clips, targets in self.datamodule.train_loader:
            clips = clips.to(ctx.device, non_blocking=True)
            targets = targets.to(ctx.device, non_blocking=True)

            self.optimizer.zero_grad(set_to_none=True)
            with torch.autocast(device_type=ctx.device.type, dtype=amp_dtype, enabled=use_amp):
                logits = self.model(clips)
                loss = criterion(logits, targets)

            if cfg.amp == "fp16":
                self.scaler.scale(loss).backward()
                self.scaler.step(self.optimizer)
                self.scaler.update()
            else:  # bf16 / no -> no loss scaling needed
                loss.backward()
                self.optimizer.step()

            self.global_step += 1
            if ctx.is_main and self.global_step % cfg.log_every == 0:
                rate = cfg.log_every / (time.time() - t0 + 1e-9)
                log.info(
                    "[epoch %d step %d] loss=%.4f (%.2f it/s)",
                    epoch,
                    self.global_step,
                    loss.item(),
                    rate,
                )
                t0 = time.time()

            if self.global_step % cfg.checkpoint_every_steps == 0:
                self._save_checkpoint(epoch, self.global_step)

    @torch.no_grad()
    def _evaluate(self) -> dict:
        cfg, ctx = self.cfg, self.ctx
        self.model.eval()
        use_amp = cfg.amp != "no" and ctx.device.type == "cuda"
        amp_dtype = AMP_DTYPE.get(cfg.amp, torch.bfloat16)
        top1 = torch.zeros((), device=ctx.device)
        top5 = torch.zeros((), device=ctx.device)
        total = torch.zeros((), device=ctx.device)

        for clips, targets in self.datamodule.val_loader:
            clips = clips.to(ctx.device, non_blocking=True)
            targets = targets.to(ctx.device, non_blocking=True)
            with torch.autocast(device_type=ctx.device.type, dtype=amp_dtype, enabled=use_amp):
                logits = self.model(clips)
            acc = accuracy(logits, targets, ks=(1, 5))
            top1 += acc[1]
            top5 += acc[5]
            total += targets.size(0)

        top1 = all_reduce_mean(top1 / total.clamp(min=1))
        top5 = all_reduce_mean(top5 / total.clamp(min=1))
        return {"top1": top1.item(), "top5": top5.item()}

    def fit(self) -> None:
        cfg, ctx = self.cfg, self.ctx
        for epoch in range(self.start_epoch, cfg.epochs):
            with self.tracer.start_as_current_span("epoch") as span:
                span.set_attribute("epoch", epoch)
                if self.datamodule.train_sampler is not None:
                    self.datamodule.train_sampler.set_epoch(epoch)

                # Unfreeze the backbone once warmup ends (discriminative fine-tuning).
                if (
                    self.use_warmup
                    and epoch == cfg.freeze_backbone_epochs
                    and self._unwrap().encoder._frozen
                ):
                    self._unwrap().set_backbone_trainable(True)
                    self.optimizer, self.scheduler = self._build_optim_sched(epoch)
                    span.set_attribute("backbone_unfrozen", True)
                    if ctx.is_main:
                        log.info(
                            "unfroze backbone at epoch %d (backbone lr=%g)",
                            epoch,
                            cfg.lr * cfg.backbone_lr_mult,
                        )

                with self.tracer.start_as_current_span("train_epoch"):
                    self._train_epoch(epoch)
                self.scheduler.step()

                with self.tracer.start_as_current_span("evaluate"):
                    metrics = self._evaluate()
                span.set_attribute("val_top1", metrics["top1"])
                span.set_attribute("val_top5", metrics["top5"])
                if ctx.is_main:
                    log.info(
                        "== epoch %d val top1=%.4f top5=%.4f ==",
                        epoch,
                        metrics["top1"],
                        metrics["top5"],
                    )
                    self.tracker.log_metrics(
                        {
                            "val_top1": metrics["top1"],
                            "val_top5": metrics["top5"],
                            "lr": self.optimizer.param_groups[0]["lr"],
                        },
                        step=epoch,
                    )

                self._save_checkpoint(epoch, self.global_step)  # end-of-epoch checkpoint

        self._log_final_artifacts()

    def _log_final_artifacts(self) -> None:
        if not self.ctx.is_main:
            return
        latest = os.path.join(self.cfg.output_dir, "latest.pt")
        if os.path.exists(latest):
            self.tracker.log_artifact(latest)
            self.tracker.log_artifact(os.path.join(self.cfg.output_dir, "label_map.json"))
