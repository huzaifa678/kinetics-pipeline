"""Distributed helpers: read the torchrun env vars and initialize DDP/NCCL.

Reads RANK, WORLD_SIZE, LOCAL_RANK, MASTER_ADDR, MASTER_PORT. Single source of
truth for "are we distributed, and on which device". Everything is a thin, safe
wrapper over ``torch.distributed`` that degrades to a no-op in single-process /
CPU runs, so the same code path works under ``torchrun`` on HyperPod GPUs, in CI,
and on a laptop.
"""

from __future__ import annotations

import datetime as _dt
import os
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass

import torch
import torch.distributed as dist

from .observability import get_logger

log = get_logger(__name__)

# NCCL collectives can stall on a slow/failed peer; a bounded timeout turns an
# infinite hang into a surfaced error (overridable for very large jobs).
_DEFAULT_TIMEOUT_MIN = int(os.environ.get("DDP_TIMEOUT_MINUTES", "30"))


@dataclass(frozen=True)
class DistContext:
    """Immutable snapshot of the process's place in the job."""

    device: torch.device
    rank: int
    world_size: int
    local_rank: int
    distributed: bool

    @property
    def is_main(self) -> bool:
        """True on the single global coordinator (rank 0).

        Gate logging, checkpointing and experiment tracking on this.
        """
        return self.rank == 0

    @property
    def is_local_main(self) -> bool:
        """True once per node (local_rank 0).

        Gate per-node work such as downloading shared artifacts to local disk.
        """
        return self.local_rank == 0


def _env_int(name: str, default: int) -> int:
    """Parse an int env var, falling back (with a warning) on garbage values.

    Avoids crashing the whole job over a malformed launcher env.
    """
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        log.warning("env %s=%r is not an int; using default %d", name, raw, default)
        return default


def is_dist_avail_and_initialized() -> bool:
    return dist.is_available() and dist.is_initialized()


def get_rank() -> int:
    return dist.get_rank() if is_dist_avail_and_initialized() else 0


def get_world_size() -> int:
    return dist.get_world_size() if is_dist_avail_and_initialized() else 1


def scaled_lr(base_lr: float, mode: str, world_size: int) -> float:
    """Scale the base LR for the global (multi-rank) batch.

    Global batch = per-GPU batch * world_size, so the LR usually grows with it:
    "linear" = base_lr * world_size (large-batch SGD rule), "sqrt" = base_lr *
    sqrt(world_size) (gentler, common for Adam), "none" = unchanged. world_size==1
    or mode "none" leaves it untouched, so single-node runs are unaffected.
    """
    if mode == "linear":
        return base_lr * world_size
    if mode == "sqrt":
        return base_lr * (world_size**0.5)
    return base_lr


def setup_distributed(timeout_minutes: int | None = None) -> DistContext:
    """Resolve device + rank from the torchrun env and init the process group.

    Initializes the group only when WORLD_SIZE > 1. Idempotent: a second call
    returns the context without re-initializing.
    """
    world_size = _env_int("WORLD_SIZE", 1)
    rank = _env_int("RANK", 0)
    local_rank = _env_int("LOCAL_RANK", 0)
    distributed = world_size > 1

    if torch.cuda.is_available():
        torch.cuda.set_device(local_rank)
        device = torch.device(f"cuda:{local_rank}")
    else:
        device = torch.device("cpu")

    if distributed and not dist.is_initialized():
        backend = "nccl" if torch.cuda.is_available() else "gloo"
        minutes = _DEFAULT_TIMEOUT_MIN if timeout_minutes is None else timeout_minutes
        dist.init_process_group(
            backend=backend,
            init_method="env://",
            timeout=_dt.timedelta(minutes=minutes),
        )
        log.info(
            "initialized process group: backend=%s rank=%d/%d local_rank=%d device=%s",
            backend,
            rank,
            world_size,
            local_rank,
            device,
        )

    return DistContext(device, rank, world_size, local_rank, distributed)


def cleanup() -> None:
    """Tear down the process group.

    Safe to call unconditionally (no-op when not initialized), so it belongs in a
    ``finally``.
    """
    if is_dist_avail_and_initialized():
        dist.destroy_process_group()


@contextmanager
def distributed_context(timeout_minutes: int | None = None) -> Iterator[DistContext]:
    """Set up DDP and guarantee teardown even if the body raises.

    Without this, an exception mid-training leaks the process group and the
    surviving ranks block forever in NCCL. Use as::

        with distributed_context() as ctx:
            train(ctx)
    """
    ctx = setup_distributed(timeout_minutes)
    try:
        yield ctx
    finally:
        cleanup()


def barrier() -> None:
    """Synchronize all ranks.

    Passes device_ids on NCCL so the barrier runs on the right GPU (avoids the
    PyTorch warning and a wrong-device hang).
    """
    if not is_dist_avail_and_initialized():
        return
    if dist.get_backend() == "nccl":
        dist.barrier(device_ids=[_env_int("LOCAL_RANK", 0)])
    else:
        dist.barrier()


def all_reduce_mean(value: torch.Tensor) -> torch.Tensor:
    """Average a scalar/tensor across all ranks, returning a new tensor.

    The caller's input is never mutated in place (a SUM all-reduce would otherwise
    corrupt a value the caller still reads).
    """
    if not is_dist_avail_and_initialized():
        return value
    reduced = value.clone()
    dist.all_reduce(reduced, op=dist.ReduceOp.SUM)
    reduced /= dist.get_world_size()
    return reduced
