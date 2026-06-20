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
from .distributed import DistContext, get_world_size

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


def build_webdataset(  # noqa: ANN201
    shards: str,
    frame_size: int,
    train: bool,
    distributed: bool,
    world_size: int = 1,
    epoch_size: int = 0,
):
    """Stream pre-decoded WebDataset shards (from kinetics_trainer.etl) as (clip, label).

    Each shard sample is ``{NNN.jpg per frame, cls.txt: <idx>}``; frames decode to
    uint8 HWC, stack to a (T,H,W,3) clip, then the clip transform (resize/crop/flip/
    normalize) is applied here so augmentation stays at train time. webdataset is
    imported lazily (only shards mode needs it).

    Two epoch strategies:

    * **DDP-safe** (train + ``epoch_size > 0``): ``resampled=True`` makes each rank
      independently resample from *all* shards (no partitioning), and ``with_epoch``
      caps every rank to ``epoch_size / world_size`` samples — so ranks always do the
      same number of steps and never desync on uneven shard counts. An "epoch" is
      statistical (sampling with replacement), the standard large-scale DDP pattern.
    * **Single pass** (eval, or train with ``epoch_size == 0``): ``split_by_node``
      gives each rank a shard subset, one pass = one epoch. Fine for 1 node / eval.
    """
    import webdataset as wds

    transform = build_transform(frame_size, train)

    def _to_pair(sample: dict) -> tuple[torch.Tensor, int]:
        # Frames are stored as NNN.jpg (decoded to uint8 HWC by decode("rgb8")):
        # sort by key and stack back into a (T,H,W,3) clip for ClipTransform.
        frame_keys = sorted(k for k in sample if k.endswith(".jpg"))
        clip = np.stack([sample[k] for k in frame_keys], axis=0)
        return transform(clip), int(sample["cls.txt"])

    if train and epoch_size > 0:
        ds = wds.WebDataset(shards, resampled=True, shardshuffle=True, empty_check=False)
        ds = ds.shuffle(1000).decode("rgb8").map(_to_pair)
        return ds.with_epoch(max(1, epoch_size // max(1, world_size)))

    ds = wds.WebDataset(
        shards,
        shardshuffle=train,
        nodesplitter=wds.split_by_node if distributed else None,
        empty_check=False,
    )
    if train:
        ds = ds.shuffle(1000)
    return ds.decode("rgb8").map(_to_pair)


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
        # Label map always comes from the train manifest — its sorted-unique ordering
        # is what the ETL shard cls indices were written against.
        self.label_map = build_label_map(cfg.train_manifest)

        if cfg.data_format == "shards":
            return self._setup_shards()

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

    def _setup_shards(self) -> KineticsDataModule:
        """Build WebDataset (IterableDataset) loaders from pre-decoded shards."""
        import hashlib

        cfg, ctx = self.cfg, self.ctx
        dist = ctx.distributed
        ws = get_world_size()
        train_ds = build_webdataset(
            cfg.train_shards,
            cfg.frame_size,
            train=True,
            distributed=dist,
            world_size=ws,
            epoch_size=cfg.shard_epoch_size,
        )
        val_ds = build_webdataset(cfg.val_shards, cfg.frame_size, train=False, distributed=dist)
        self.train_loader = DataLoader(
            train_ds,
            batch_size=cfg.batch_size,
            num_workers=cfg.num_workers,
            pin_memory=True,
            drop_last=True,
            persistent_workers=cfg.num_workers > 0,
        )
        self.val_loader = DataLoader(
            val_ds,
            batch_size=cfg.batch_size,
            num_workers=cfg.num_workers,
            pin_memory=True,
            persistent_workers=cfg.num_workers > 0,
        )
        # IterableDataset -> no DistributedSampler (wds splits shards by node/worker).
        self.train_sampler = None
        key = f"{cfg.train_shards}|{cfg.val_shards}".encode()
        self.data_hash = hashlib.sha256(key).hexdigest()[:16]
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
