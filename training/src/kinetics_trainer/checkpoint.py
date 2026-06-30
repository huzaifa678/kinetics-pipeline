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

import concurrent.futures
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
        checkpoint_dir: str = "",
        async_upload: bool = False,
    ) -> None:
        self.output_dir = output_dir
        # Where checkpoints are written. Point this at the FSx-for-Lustre mount
        # (e.g. /data/checkpoints) for fast shared writes during HyperPod
        # auto-resume; the S3 mirror below is the durable copy. Defaults to
        # output_dir so existing runs are unchanged.
        self.dir = checkpoint_dir or output_dir
        self.s3_prefix = s3_prefix.rstrip("/") if s3_prefix else ""
        self.is_main = is_main
        if storage is not None:
            self.storage: RemoteStorage = storage
        else:
            self.storage = S3Storage() if self.s3_prefix else NullStorage()
        # Async S3 mirror: a single background worker so the (fast) FSx write
        # returns to the training loop without blocking on the S3 PUT. flush()
        # joins outstanding uploads (call before exit). Only when mirroring to S3.
        self.async_upload = bool(async_upload and self.s3_prefix)
        self._executor = (
            concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="ckpt-upload")
            if self.async_upload
            else None
        )
        self._pending: list[concurrent.futures.Future] = []

    @property
    def latest_path(self) -> str:
        """Local path of the latest checkpoint (on FSx when checkpoint_dir is set)."""
        return os.path.join(self.dir, LATEST)

    def _remote_uri(self, tag: str) -> str:
        return f"{self.s3_prefix}/{tag}" if self.s3_prefix else ""

    def save(self, state: dict[str, Any], tag: str = LATEST) -> None:
        """Atomic local write (tmp + rename) then optional remote mirror.

        No-op on non-main ranks. The S3 mirror is async when async_upload is set.
        """
        if not self.is_main:
            return
        os.makedirs(self.dir, exist_ok=True)
        local = os.path.join(self.dir, tag)
        tmp = local + ".tmp"
        torch.save(state, tmp)
        os.replace(tmp, local)
        if not self.s3_prefix:
            return
        if self.async_upload:
            self._pending.append(
                self._executor.submit(self.storage.upload, local, self._remote_uri(tag))
            )
        else:
            self.storage.upload(local, self._remote_uri(tag))

    def flush(self) -> None:
        """Block until all in-flight async uploads finish. Safe to call always."""
        for f in self._pending:
            f.result()
        self._pending.clear()

    def load_latest(self, map_location: Any = "cpu") -> dict[str, Any] | None:
        """Prefer a local checkpoint; else pull latest.pt from remote storage.

        Returns None when there is nothing to resume from (a fresh run).
        """
        local = os.path.join(self.dir, LATEST)
        if not os.path.exists(local) and self.s3_prefix:
            self.storage.download(self._remote_uri(LATEST), local)
        if os.path.exists(local):
            return torch.load(local, map_location=map_location, weights_only=False)
        return None
