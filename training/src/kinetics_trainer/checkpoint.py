"""Checkpoint persistence: local atomic write + optional remote mirror.

Writes locally then mirrors to remote storage so that when the HyperPod training
operator restarts the job after a fault, training resumes from the latest
checkpoint instead of from scratch.

Design — persistence is decoupled from the storage backend:

* ``RemoteStorage`` (Protocol) is the seam. ``CheckpointManager`` depends on this
  abstraction, not on boto3 (DIP), so it's unit-testable with a fake and a new
  backend (GCS, ...) is a new class rather than an edit here (OCP).
* ``S3Storage`` is the production backend (lazy boto3 client, injectable for
  tests); ``NullStorage`` is the no-op used for local-only runs.
"""

from __future__ import annotations

import os
from typing import Any, Protocol
from urllib.parse import urlparse

import torch

LATEST = "latest.pt"


def _split_s3(uri: str) -> tuple[str, str]:
    u = urlparse(uri)
    return u.netloc, u.path.lstrip("/")


class RemoteStorage(Protocol):
    """Minimal object-store contract the CheckpointManager mirrors through."""

    def upload(self, local_path: str, uri: str) -> None: ...

    def download(self, uri: str, local_path: str) -> bool:
        """Return True if the object existed and was fetched, else False."""
        ...


class NullStorage:
    """No remote mirror — used for local-only runs (no checkpoint_s3)."""

    def upload(self, local_path: str, uri: str) -> None:
        return None

    def download(self, uri: str, local_path: str) -> bool:
        return False


class S3Storage:
    """S3-backed RemoteStorage.

    The boto3 client is created lazily (so importing this module never requires
    boto3) and is injectable for tests.
    """

    def __init__(self, client: Any = None) -> None:
        self._client = client

    @property
    def client(self) -> Any:
        if self._client is None:
            import boto3

            self._client = boto3.client("s3")
        return self._client

    def upload(self, local_path: str, uri: str) -> None:
        bucket, key = _split_s3(uri)
        self.client.upload_file(local_path, bucket, key)

    def download(self, uri: str, local_path: str) -> bool:
        bucket, key = _split_s3(uri)
        try:
            self.client.head_object(Bucket=bucket, Key=key)
        except Exception:
            return False
        os.makedirs(os.path.dirname(local_path) or ".", exist_ok=True)
        self.client.download_file(bucket, key, local_path)
        return True


class CheckpointManager:
    """Local atomic write + resume; delegates remote mirroring to a RemoteStorage.

    Only the main process persists (gated once here, so callers don't repeat the
    rank check).
    """

    def __init__(
        self,
        output_dir: str,
        s3_prefix: str = "",
        storage: RemoteStorage | None = None,
        is_main: bool = True,
    ) -> None:
        self.output_dir = output_dir
        self.s3_prefix = s3_prefix.rstrip("/") if s3_prefix else ""
        self.is_main = is_main
        if storage is not None:
            self.storage: RemoteStorage = storage
        else:
            self.storage = S3Storage() if self.s3_prefix else NullStorage()

    def _remote_uri(self, tag: str) -> str:
        return f"{self.s3_prefix}/{tag}" if self.s3_prefix else ""

    def save(self, state: dict[str, Any], tag: str = LATEST) -> None:
        """Atomic local write (tmp + rename) then optional remote mirror.

        No-op on non-main ranks.
        """
        if not self.is_main:
            return
        os.makedirs(self.output_dir, exist_ok=True)
        local = os.path.join(self.output_dir, tag)
        tmp = local + ".tmp"
        torch.save(state, tmp)
        os.replace(tmp, local)
        if self.s3_prefix:
            self.storage.upload(local, self._remote_uri(tag))

    def load_latest(self, map_location: Any = "cpu") -> dict[str, Any] | None:
        """Prefer a local checkpoint; else pull latest.pt from remote storage.

        Returns None when there is nothing to resume from (a fresh run).
        """
        local = os.path.join(self.output_dir, LATEST)
        if not os.path.exists(local) and self.s3_prefix:
            self.storage.download(self._remote_uri(LATEST), local)
        if os.path.exists(local):
            return torch.load(local, map_location=map_location, weights_only=False)
        return None
