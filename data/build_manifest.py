"""Build train/val manifests from a class-foldered video tree and stamp a
dataset version. Pairs with DVC: you version the *manifests* (small), not the
raw video (TBs, already immutable via S3 bucket versioning).

Expected layout (Kinetics-style):
    <videos-root>/<class_name>/<clip>.mp4

    python data/build_manifest.py --videos-root /data/kinetics400 \
        --out-dir data/manifests --val-split 0.1
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import os
import random

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("build_manifest")

VIDEO_EXT = {".mp4", ".avi", ".mkv", ".webm", ".mov"}


def scan(root: str) -> list[tuple[str, str]]:
    rows = []
    for cls in sorted(os.listdir(root)):
        cdir = os.path.join(root, cls)
        if not os.path.isdir(cdir):
            continue
        for fn in sorted(os.listdir(cdir)):
            if os.path.splitext(fn)[1].lower() in VIDEO_EXT:
                rows.append((os.path.join(cls, fn), cls))
    return rows


def write_csv(path: str, rows: list[tuple[str, str]]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["path", "label"])
        w.writerows(rows)


def file_hash(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()[:16]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--videos-root", required=True)
    ap.add_argument("--out-dir", default="data/manifests")
    ap.add_argument("--val-split", type=float, default=0.1)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--source-uri", default="", help="e.g. s3://bucket/kinetics400 (recorded in version)")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    rows = scan(args.videos_root)
    if not rows:
        raise SystemExit(f"no videos found under {args.videos_root}")
    random.Random(args.seed).shuffle(rows)

    n_val = int(len(rows) * args.val_split)
    val, train = rows[:n_val], rows[n_val:]
    train_csv = os.path.join(args.out_dir, "train.csv")
    val_csv = os.path.join(args.out_dir, "val.csv")
    write_csv(train_csv, train)
    write_csv(val_csv, val)
    log.info("wrote %d train / %d val rows to %s", len(train), len(val), args.out_dir)

    classes = sorted({c for _, c in rows})
    version = {
        "source_uri": args.source_uri or args.videos_root,
        "num_classes": len(classes),
        "num_train": len(train),
        "num_val": len(val),
        "train_sha256": file_hash(train_csv),
        "val_sha256": file_hash(val_csv),
        "seed": args.seed,
    }
    with open(os.path.join(args.out_dir, "dataset_version.json"), "w") as f:
        json.dump(version, f, indent=2)
    print(json.dumps(version, indent=2))


if __name__ == "__main__":
    main()
