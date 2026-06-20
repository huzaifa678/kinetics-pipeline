"""Smoke tests for the offline ETL shard builder.

Skipped unless webdataset + pandas + torch are importable. PyAV decode is stubbed,
so no real video / av is needed — we exercise the shard write + read round-trip.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

pytest.importorskip("webdataset")
pytest.importorskip("pandas")
pytest.importorskip("torch")

import numpy as np
import webdataset as wds

import kinetics_trainer.etl.build_shards as bs


@pytest.fixture()
def manifest(tmp_path):
    p = tmp_path / "train.csv"
    p.write_text("path,label\na.mp4,jump\nb.mp4,run\nc.mp4,jump\n")
    return str(p)


def test_build_label_map_sorted(manifest):
    import pandas as pd

    assert bs.build_label_map(pd.read_csv(manifest)) == {"jump": 0, "run": 1}


def _fake_decode(size):
    return lambda path, n: np.zeros((n, size, size, 3), dtype=np.uint8)


def test_build_shards_roundtrip(manifest, tmp_path):
    out = str(tmp_path / "shards")
    written = bs.build_shards(
        manifest,
        out,
        clip_length=4,
        resize=32,
        num_shards=1,
        shard_id=0,
        decode_fn=_fake_decode(40),
    )
    assert written == 3
    assert os.path.exists(os.path.join(out, "label_map.json"))

    samples = list(wds.WebDataset(os.path.join(out, "clips-00000.tar")).decode("rgb8"))
    assert len(samples) == 3
    # Frames stored as NNN.jpg (T of them); each decodes to a resized HWC uint8 image.
    frame_keys = sorted(k for k in samples[0] if k.endswith(".jpg"))
    assert len(frame_keys) == 4  # T preserved
    assert samples[0][frame_keys[0]].shape == (32, 32, 3)  # resized
    assert samples[0]["cls.txt"] in {"0", "1"}


def test_build_shards_sharding_splits_rows(manifest, tmp_path):
    out = str(tmp_path / "shards")
    # 3 rows over 2 shards -> rows [0,2] and [1] = 2 + 1.
    assert bs.build_shards(manifest, out, num_shards=2, shard_id=0, decode_fn=_fake_decode(16)) == 2
    assert bs.build_shards(manifest, out, num_shards=2, shard_id=1, decode_fn=_fake_decode(16)) == 1


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
