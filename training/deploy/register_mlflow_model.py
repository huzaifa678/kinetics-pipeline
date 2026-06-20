"""Register a CNN-LSTM artifact into the (SageMaker-managed) MLflow Model Registry.

The MLflow registry is the source of truth for which model versions are
deployable; Seldon then pulls the resolved S3 artifact. Auth to a SageMaker-managed
MLflow server is SigV4 via the ``sagemaker-mlflow`` plugin — just pass the
tracking-server ARN as the tracking URI.

    python deploy/register_mlflow_model.py \
        --model-dir /opt/ml/model \
        --name kinetics-cnn-lstm \
        --tracking-uri arn:aws:sagemaker:us-east-1:ACCT:mlflow-tracking-server/... \
        --alias challenger

The model dir must contain ``model.pth`` + ``model_config.json`` + ``label_map.json``
(the layout Predictor / KineticsRuntime load). It is logged as the run's ``model``
artifact and a new registry version is created pointing at it. ``--alias`` optionally
tags the version.
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

log = get_logger("kinetics_register_mlflow")

# Artifact subpath under the run; resolve_seldon_uri.py returns the URI to it.
ARTIFACT_PATH = "model"
DEFAULT_NAME = "kinetics-cnn-lstm"


def register(
    model_dir: str,
    name: str = DEFAULT_NAME,
    tracking_uri: str = "",
    run_name: str | None = None,
    alias: str | None = None,
    experiment: str = DEFAULT_NAME,
) -> str:
    """Log the model dir, register a new version, optionally set an alias."""
    if tracking_uri:
        mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(experiment)
    with mlflow.start_run(run_name=run_name) as run:
        mlflow.log_artifacts(model_dir, artifact_path=ARTIFACT_PATH)
        model_uri = f"runs:/{run.info.run_id}/{ARTIFACT_PATH}"
        version = mlflow.register_model(model_uri=model_uri, name=name).version
    log.info("registered %s version %s", name, version)
    if alias:
        MlflowClient().set_registered_model_alias(name, alias, version)
        log.info("alias %s -> %s v%s", alias, name, version)
    return version


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    p = argparse.ArgumentParser(description="Register a model dir into the MLflow Model Registry.")
    p.add_argument("--model-dir", required=True)
    p.add_argument("--name", default=DEFAULT_NAME)
    p.add_argument("--tracking-uri", default=os.environ.get("MLFLOW_TRACKING_URI", ""))
    p.add_argument("--run-name", default=os.environ.get("RUN_NAME"))
    p.add_argument("--experiment-name", default=DEFAULT_NAME)
    p.add_argument("--alias", default=None, help="MLflow 2.x alias, e.g. champion / challenger")
    return p.parse_args(argv)


def main() -> None:
    """Register, then print the new version number for CI capture."""
    args = parse_args()
    version = register(
        model_dir=args.model_dir,
        name=args.name,
        tracking_uri=args.tracking_uri,
        run_name=args.run_name,
        alias=args.alias,
        experiment=args.experiment_name,
    )
    print(version)


if __name__ == "__main__":
    main()
