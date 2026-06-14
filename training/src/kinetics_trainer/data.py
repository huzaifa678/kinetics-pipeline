"""Kinetics clip dataset.

Manifest = CSV with header `path,label`. `path` is a video file (absolute, or
relative to the manifest dir / the FSx mount at /data). `label` is either a
class name (string) or an integer class index. A deterministic label map is
built from the sorted unique labels of the training manifest.
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable

import av
import numpy as np
import pandas as pd
import torch
import torchvision.transforms.functional as F
from torch.utils.data import DataLoader, Dataset, DistributedSampler

from .config import Config
from .distributed import DistContext

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def _sample_indices(total: int, num: int) -> list[int]:
    """Uniformly spaced frame indices; pad by repeating the last if too short."""
    if total <= 0:
        return [0] * num
    if total >= num:
        step = total / num
        return [min(total - 1, int(i * step)) for i in range(num)]
    return list(range(total)) + [total - 1] * (num - total)


def decode_clip(path: str, num_frames: int) -> np.ndarray:
    """Decode `num_frames` uniformly sampled RGB frames -> (T, H, W, 3) uint8."""
    with av.open(path) as container:
        stream = container.streams.video[0]
        stream.thread_type = "AUTO"
        total = stream.frames or 0
        if total == 0:  # some containers don't report frame count
            duration = float(stream.duration * stream.time_base) if stream.duration else 0.0
            fps = float(stream.average_rate) if stream.average_rate else 25.0
            total = max(1, int(duration * fps))
        wanted = set(_sample_indices(total, num_frames))
        frames: dict[int, np.ndarray] = {}
        for i, frame in enumerate(container.decode(stream)):
            if i in wanted:
                frames[i] = frame.to_ndarray(format="rgb24")
            if len(frames) >= len(wanted):
                break

    ordered = _sample_indices(total, num_frames)
    if not frames:  # decode failed -> black clip, keeps the batch alive
        h = w = 224
        return np.zeros((num_frames, h, w, 3), dtype=np.uint8)
    ref = next(iter(frames.values()))
    return np.stack([frames.get(i, ref) for i in ordered], axis=0)


class ClipTransform:
    """Spatial transform applied to a whole clip at once (one crop box + flip per clip).

    Using the SAME crop box and flip decision for every frame avoids the temporal
    jitter that per-frame random params would introduce, preserving the continuity
    the LSTM learns from. Input (T,H,W,3) uint8 -> (T,3,H,W) float.
    """

    def __init__(self, frame_size: int, train: bool) -> None:
        self.frame_size = frame_size
        self.train = train
        self.resize = int(frame_size * 1.15)

    def __call__(self, clip: np.ndarray) -> torch.Tensor:
        x = torch.from_numpy(clip).permute(0, 3, 1, 2).contiguous().float().div_(255.0)
        x = F.resize(x, [self.resize], antialias=True)  # shorter side -> resize
        _, _, h, w = x.shape
        s = self.frame_size
        if self.train:
            i = int(torch.randint(0, h - s + 1, (1,)).item())
            j = int(torch.randint(0, w - s + 1, (1,)).item())
            x = F.crop(x, i, j, s, s)
            if torch.rand(1).item() < 0.5:
                x = F.hflip(x)
        else:
            x = F.center_crop(x, [s, s])
        return F.normalize(x, IMAGENET_MEAN, IMAGENET_STD)


def build_transform(frame_size: int, train: bool) -> Callable:
    return ClipTransform(frame_size, train)


class KineticsClipDataset(Dataset):
    """Map-style dataset of (clip_tensor, label) pairs from a path,label manifest."""

    def __init__(
        self,
        manifest: str,
        clip_length: int,
        frame_size: int,
        label_map: dict[str, int],
        train: bool,
    ) -> None:
        self.df = pd.read_csv(manifest)
        if not {"path", "label"}.issubset(self.df.columns):
            raise ValueError("manifest must have columns: path,label")
        self.root = os.path.dirname(os.path.abspath(manifest))
        self.clip_length = clip_length
        self.label_map = label_map
        self.transform = build_transform(frame_size, train)

    def __len__(self) -> int:
        return len(self.df)

    def _resolve(self, p: str) -> str:
        return p if os.path.isabs(p) else os.path.join(self.root, p)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        row = self.df.iloc[idx]
        clip = decode_clip(self._resolve(str(row["path"])), self.clip_length)  # (T,H,W,3)
        clip_t = self.transform(clip)  # (T,3,H,W)
        label = self.label_map[str(row["label"])]
        return clip_t, label


def build_label_map(train_manifest: str) -> dict[str, int]:
    labels = sorted(pd.read_csv(train_manifest)["label"].astype(str).unique())
    return {name: i for i, name in enumerate(labels)}


class KineticsDataModule:
    """Owns dataset/dataloader construction (Lightning-style).

    The Trainer depends on this seam rather than on pandas/av/DataLoader wiring.
    Call ``setup()`` once before training; loaders + label_map + data_hash are then
    available as attributes.
    """

    def __init__(self, cfg: Config, ctx: DistContext) -> None:
        self.cfg = cfg
        self.ctx = ctx
        self.label_map: dict[str, int] | None = None
        self.data_hash: str | None = None
        self.train_loader: DataLoader | None = None
        self.val_loader: DataLoader | None = None
        self.train_sampler: DistributedSampler | None = None

    def setup(self) -> KineticsDataModule:
        cfg, ctx = self.cfg, self.ctx
        self.label_map = build_label_map(cfg.train_manifest)
        train_ds = KineticsClipDataset(
            cfg.train_manifest, cfg.clip_length, cfg.frame_size, self.label_map, train=True
        )
        val_ds = KineticsClipDataset(
            cfg.val_manifest, cfg.clip_length, cfg.frame_size, self.label_map, train=False
        )

        self.train_sampler = DistributedSampler(train_ds, shuffle=True) if ctx.distributed else None
        val_sampler = DistributedSampler(val_ds, shuffle=False) if ctx.distributed else None

        self.train_loader = DataLoader(
            train_ds,
            batch_size=cfg.batch_size,
            sampler=self.train_sampler,
            shuffle=self.train_sampler is None,
            num_workers=cfg.num_workers,
            pin_memory=True,
            drop_last=True,
            persistent_workers=cfg.num_workers > 0,
        )
        self.val_loader = DataLoader(
            val_ds,
            batch_size=cfg.batch_size,
            sampler=val_sampler,
            shuffle=False,
            num_workers=cfg.num_workers,
            pin_memory=True,
            persistent_workers=cfg.num_workers > 0,
        )
        self.data_hash = manifest_hash(cfg.train_manifest, cfg.val_manifest)
        return self


def save_label_map(label_map: dict[str, int], path: str) -> None:
    with open(path, "w") as f:
        json.dump(label_map, f, indent=2)


def manifest_hash(*paths: str) -> str:
    """Short content hash of the manifest files.

    Logged per run so an experiment is reproducible against an exact dataset
    snapshot.
    """
    import hashlib

    h = hashlib.sha256()
    for p in sorted(paths):
        with open(p, "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:16]
