"""Tests for the MLflow registry -> Seldon S3 URI bridge (deploy/ scripts).

Skipped unless mlflow is importable. The MlflowClient and mlflow module calls are
replaced with fakes, so no real tracking server is needed.
"""

import contextlib
import os
import sys
import types

import pytest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "deploy"))
sys.path.insert(0, os.path.join(HERE, "..", "src"))

pytest.importorskip("mlflow")

import register_mlflow_model as rm
import resolve_seldon_uri as rs


class _MV:
    def __init__(self, version):
        self.version = version


class _FakeClient:
    def __init__(self):
        self.alias_set = None
        self._versions = [_MV("1"), _MV("5"), _MV("2")]

    def get_model_version_by_alias(self, name, alias):
        return _MV("7")

    def get_model_version_download_uri(self, name, version):
        return f"s3://bucket/artifacts/{name}/{version}/model"

    def search_model_versions(self, filt):
        return self._versions

    def set_registered_model_alias(self, name, alias, version):
        self.alias_set = (name, alias, version)


def test_resolve_by_alias(monkeypatch):
    monkeypatch.setattr(rs, "MlflowClient", _FakeClient)
    assert rs.resolve("kinetics-cnn-lstm", alias="champion").endswith("/7/model")


def test_resolve_by_version(monkeypatch):
    monkeypatch.setattr(rs, "MlflowClient", _FakeClient)
    assert rs.resolve("m", version="3").endswith("/3/model")


def test_resolve_latest_picks_highest(monkeypatch):
    monkeypatch.setattr(rs, "MlflowClient", _FakeClient)
    assert rs.resolve("m").endswith("/5/model")


def test_resolve_no_versions_raises(monkeypatch):
    fc = _FakeClient()
    fc._versions = []
    monkeypatch.setattr(rs, "MlflowClient", lambda: fc)
    with pytest.raises(ValueError, match="no versions"):
        rs.resolve("m")


def test_register_sets_alias(monkeypatch):
    fc = _FakeClient()
    monkeypatch.setattr(rm, "MlflowClient", lambda: fc)
    monkeypatch.setattr(rm.mlflow, "set_tracking_uri", lambda u: None)
    monkeypatch.setattr(rm.mlflow, "set_experiment", lambda e: None)
    monkeypatch.setattr(rm.mlflow, "log_artifacts", lambda d, artifact_path=None: None)
    monkeypatch.setattr(rm.mlflow, "register_model", lambda model_uri, name: _MV("9"))

    @contextlib.contextmanager
    def fake_run(run_name=None):
        yield types.SimpleNamespace(info=types.SimpleNamespace(run_id="abc"))

    monkeypatch.setattr(rm.mlflow, "start_run", fake_run)

    version = rm.register("/tmp/model", name="kinetics-cnn-lstm", alias="challenger")
    assert version == "9"
    assert fc.alias_set == ("kinetics-cnn-lstm", "challenger", "9")


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
