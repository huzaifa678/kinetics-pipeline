"""Resolve an MLflow Model Registry entry to its S3 artifact URI for Seldon.

Seldon Core v2 pulls model artifacts straight from S3 (rclone + IRSA) — it does
not speak MLflow's ``models:/`` protocol or SageMaker SigV4. This bridges the two:
given a registry name + alias/version, it prints the underlying S3 URI to feed
into a Seldon ``Model``'s ``spec.storageUri`` (CI yq-bumps the CD repo with it).

    python deploy/resolve_seldon_uri.py \
        --name kinetics-cnn-lstm --alias champion \
        --tracking-uri arn:aws:sagemaker:us-east-1:ACCT:mlflow-tracking-server/...

Resolution order: ``--alias``, else
``--version``, else the highest version number. The printed URI points at the
``model`` artifact dir (model.pth + model_config.json + label_map.json), which is
exactly what KineticsRuntime / Predictor load.
"""

from __future__ import annotations

import argparse
import os
import sys

import mlflow
from mlflow.tracking import MlflowClient

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "src"))
from kinetics_trainer.observability import get_logger  # noqa: E402

log = get_logger("kinetics_resolve_seldon_uri")

DEFAULT_NAME = "kinetics-cnn-lstm"


def resolve(
    name: str,
    tracking_uri: str = "",
    version: str | None = None,
    alias: str | None = None,
) -> str:
    """Return the S3 artifact URI for the chosen registry version."""
    if tracking_uri:
        mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient()
    if alias:
        resolved = client.get_model_version_by_alias(name, alias).version
    elif version:
        resolved = version
    else:
        candidates = client.search_model_versions(f"name='{name}'")
        if not candidates:
            raise ValueError(f"no versions registered for model {name!r}")
        resolved = max(candidates, key=lambda m: int(m.version)).version
    uri = client.get_model_version_download_uri(name, resolved)
    log.info("%s (%s) -> %s", name, alias or version or "latest", uri)
    return uri


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    p = argparse.ArgumentParser(description="Resolve an MLflow model version to its S3 URI.")
    p.add_argument("--name", default=DEFAULT_NAME)
    p.add_argument("--tracking-uri", default=os.environ.get("MLFLOW_TRACKING_URI", ""))
    g = p.add_mutually_exclusive_group()
    g.add_argument("--alias", default=None, help="MLflow 2.x alias, e.g. champion / challenger")
    g.add_argument("--version", default=None, help="explicit registry version")
    return p.parse_args(argv)


def main() -> None:
    """Print the resolved S3 URI (for CI to inject into the Seldon Model)."""
    args = parse_args()
    print(resolve(args.name, args.tracking_uri, args.version, args.alias))


if __name__ == "__main__":
    main()
