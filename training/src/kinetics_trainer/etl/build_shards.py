"""Decode + shard Kinetics clips into WebDataset tars (the offline ETL stage).

Reads a ``path,label`` manifest, decodes each clip once with PyAV (reusing the
trainer's ``decode_clip``), resizes to a standard size, and writes uint8 frames
into WebDataset ``.tar`` shards on a local dir or S3. Training then streams
pre-decoded frames (sequential reads, S3/FSx-friendly) instead of paying the
decode cost every epoch.

Parallelism: run N workers, each ``--shard-id i`` of ``--num-shards N``, which
process manifest rows ``[i::N]`` into their own shard. Embarrassingly parallel —
a Kubernetes Job with N completions, or N local processes.

    kinetics-build-shards \
        --manifest /data/kinetics400/train.csv \
        --output s3://<archive-bucket>/kinetics400/shards/train \
        --num-shards 64 --shard-id 0

Each sample: ``{NNN.jpg per frame (resized uint8), cls.txt: <class index>}``.
"""

from __future__ import annotations

import argparse
import os
from collections.abc import Callable

import numpy as np
import pandas as pd
import torch
import torchvision.transforms.functional as F
import webdataset as wds

from ..observability import get_logger

log = get_logger("kinetics_etl")

# Decoder signature: (path, num_frames) -> (T,H,W,3) uint8.
Decoder = Callable[[str, int], np.ndarray]


def _default_decoder() -> Decoder:
    """Lazily import the trainer's PyAV decoder (keeps this module av-free to import)."""
    from ..data import decode_clip

    return decode_clip


def build_label_map(df: pd.DataFrame) -> dict[str, int]:
    """Map class name -> index from the manifest (sorted, matches KineticsClipDataset)."""
    return {label: i for i, label in enumerate(sorted(df["label"].unique()))}


def resize_uint8(frames: np.ndarray, size: int) -> np.ndarray:
    """Resize (T,H,W,3) uint8 frames so the shorter side == size, staying uint8."""
    x = torch.from_numpy(frames).permute(0, 3, 1, 2)  # (T,3,H,W) uint8
    x = F.resize(x, [size], antialias=True)
    return x.permute(0, 2, 3, 1).contiguous().numpy()


def _sink_url(output: str, shard_id: int) -> str:
    """WebDataset sink: an S3 pipe for s3:// outputs, else a local tar path."""
    name = f"clips-{shard_id:05d}.tar"
    if output.startswith("s3://"):
        return f"pipe:aws s3 cp - {output.rstrip('/')}/{name}"
    os.makedirs(output, exist_ok=True)
    return os.path.join(output, name)


def build_shards(
    manifest: str,
    output: str,
    clip_length: int = 16,
    resize: int = 256,
    num_shards: int = 1,
    shard_id: int = 0,
    decode_fn: Decoder | None = None,
) -> int:
    """Decode this worker's slice of the manifest into one WebDataset shard."""
    decode = decode_fn or _default_decoder()
    df = pd.read_csv(manifest)
    if not {"path", "label"}.issubset(df.columns):
        raise ValueError("manifest must have columns: path,label")
    label_map = build_label_map(df)
    root = os.path.dirname(os.path.abspath(manifest))

    # Shard 0 drops a label_map.json next to local output so consumers share indices.
    if shard_id == 0 and not output.startswith("s3://"):
        os.makedirs(output, exist_ok=True)
        with open(os.path.join(output, "label_map.json"), "w") as f:
            import json

            json.dump(label_map, f)

    written = 0
    with wds.TarWriter(_sink_url(output, shard_id)) as sink:
        for n, (_, row) in enumerate(df.iloc[shard_id::num_shards].iterrows()):
            path = row["path"]
            if not os.path.isabs(path):
                path = os.path.join(root, path)
            frames = resize_uint8(decode(path, clip_length), resize)
            # store frame as JPG for less storage usage
            sample = {"__key__": f"{shard_id:05d}_{n:06d}", "cls.txt": str(label_map[row["label"]])}
            for i in range(frames.shape[0]):
                sample[f"{i:03d}.jpg"] = frames[i]
            sink.write(sample)
            written += 1
    log.info("shard %d/%d: wrote %d samples", shard_id, num_shards, written)
    return written


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    p = argparse.ArgumentParser(description="Decode + shard Kinetics clips into WebDataset tars.")
    p.add_argument("--manifest", required=True)
    p.add_argument("--output", required=True, help="local dir or s3://bucket/prefix")
    p.add_argument("--clip-length", type=int, default=16)
    p.add_argument("--resize", type=int, default=256, help="shorter-side resize (>= frame size)")
    p.add_argument("--num-shards", type=int, default=int(os.environ.get("NUM_SHARDS", 1)))
    p.add_argument("--shard-id", type=int, default=int(os.environ.get("SHARD_ID", 0)))
    return p.parse_args(argv)


def main() -> None:
    """CLI entrypoint (kinetics-build-shards)."""
    args = parse_args()
    build_shards(
        manifest=args.manifest,
        output=args.output,
        clip_length=args.clip_length,
        resize=args.resize,
        num_shards=args.num_shards,
        shard_id=args.shard_id,
    )


if __name__ == "__main__":
    main()
