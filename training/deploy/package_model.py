"""Turn a training checkpoint into a SageMaker model artifact (model.tar.gz).

    python deploy/package_model.py \
        --checkpoint s3://.../checkpoints/cnn-lstm/latest.pt \
        --label-map  /tmp/kinetics-output/label_map.json \
        --output     s3://.../models/cnn-lstm/model.tar.gz

The archive contains model.pth + model_config.json + label_map.json, which is
exactly what inference/inference.py:model_fn expects.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tarfile
import tempfile
from urllib.parse import urlparse

import torch

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from kinetics_trainer.observability import get_logger

log = get_logger("kinetics_package")


def _is_s3(uri: str) -> bool:
    return uri.startswith("s3://")


def _download(uri: str, dst: str) -> str:
    import boto3

    u = urlparse(uri)
    boto3.client("s3").download_file(u.netloc, u.path.lstrip("/"), dst)
    return dst


def _upload(src: str, uri: str) -> None:
    import boto3

    u = urlparse(uri)
    boto3.client("s3").upload_file(src, u.netloc, u.path.lstrip("/"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True, help="latest.pt (local or s3://)")
    ap.add_argument("--label-map", required=True, help="label_map.json (local or s3://)")
    ap.add_argument("--output", required=True, help="model.tar.gz destination (local or s3://)")
    args = ap.parse_args()

    work = tempfile.mkdtemp()
    try:
        ckpt_path = (
            _download(args.checkpoint, os.path.join(work, "latest.pt"))
            if _is_s3(args.checkpoint)
            else args.checkpoint
        )
        lm_path = (
            _download(args.label_map, os.path.join(work, "label_map.json"))
            if _is_s3(args.label_map)
            else args.label_map
        )

        state = torch.load(ckpt_path, map_location="cpu", weights_only=False)
        if "config" not in state:
            raise SystemExit("checkpoint missing 'config' — was it written by this trainer?")

        bundle = os.path.join(work, "bundle")
        os.makedirs(bundle, exist_ok=True)
        torch.save(state["model"], os.path.join(bundle, "model.pth"))
        with open(os.path.join(bundle, "model_config.json"), "w") as f:
            json.dump(state["config"], f, indent=2)
        shutil.copy(lm_path, os.path.join(bundle, "label_map.json"))

        tar_local = os.path.join(work, "model.tar.gz")
        with tarfile.open(tar_local, "w:gz") as tar:
            for name in ("model.pth", "model_config.json", "label_map.json"):
                tar.add(os.path.join(bundle, name), arcname=name)

        if _is_s3(args.output):
            _upload(tar_local, args.output)
        else:
            shutil.copy(tar_local, args.output)
        log.info("wrote %s", args.output)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
