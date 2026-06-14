"""Register a model.tar.gz into the SageMaker Model Registry.

Creates a versioned Model Package, with an approval gate::

    python deploy/register_model.py \
        --model-data s3://.../models/cnn-lstm/model.tar.gz \
        --model-package-group kinetics-cnn-lstm \
        --role arn:aws:iam::<acct>:role/<sagemaker-exec-role> \
        --metrics-json /tmp/kinetics-output/metrics.json \
        --approval PendingManualApproval

Each call creates a new VERSION in the group. Promote with `--approval Approved`
(or flip status later in the console / API). deploy_endpoint.py can then deploy
the latest Approved version.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import boto3
import sagemaker
from sagemaker.model_metrics import MetricsSource, ModelMetrics
from sagemaker.pytorch import PyTorchModel

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(HERE, "..")  # training/ -> ships inference/ + src/

sys.path.insert(0, os.path.join(HERE, "..", "src"))
from kinetics_trainer.observability import get_logger  # noqa: E402

log = get_logger("kinetics_register")


def _ensure_group(sm: Any, name: str, description: str) -> None:
    try:
        sm.describe_model_package_group(ModelPackageGroupName=name)
    except sm.exceptions.ClientError:
        sm.create_model_package_group(
            ModelPackageGroupName=name, ModelPackageGroupDescription=description
        )
    except Exception:
        sm.create_model_package_group(
            ModelPackageGroupName=name, ModelPackageGroupDescription=description
        )


def _upload_metrics(metrics_json: str, bucket: str, session: Any) -> ModelMetrics | None:
    if not metrics_json or not os.path.exists(metrics_json):
        return None
    key = "model-metrics/metrics.json"
    boto3.client("s3").upload_file(metrics_json, bucket, key)
    return ModelMetrics(
        model_statistics=MetricsSource(
            content_type="application/json", s3_uri=f"s3://{bucket}/{key}"
        )
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-data", required=True)
    ap.add_argument("--model-package-group", required=True)
    ap.add_argument("--role", required=True)
    ap.add_argument("--metrics-json", default="", help="optional metrics.json to attach")
    ap.add_argument(
        "--approval",
        default="PendingManualApproval",
        choices=["PendingManualApproval", "Approved", "Rejected"],
    )
    ap.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    ap.add_argument("--framework-version", default="2.3")
    ap.add_argument("--py-version", default="py311")
    args = ap.parse_args()

    session = sagemaker.Session(boto_session=boto3.Session(region_name=args.region))
    sm = session.sagemaker_client
    _ensure_group(sm, args.model_package_group, "Kinetics CNN-LSTM action recognizer")

    model = PyTorchModel(
        model_data=args.model_data,
        role=args.role,
        entry_point="inference.py",
        source_dir=SOURCE_DIR,
        framework_version=args.framework_version,
        py_version=args.py_version,
        sagemaker_session=session,
    )
    model_metrics = _upload_metrics(args.metrics_json, session.default_bucket(), session)

    pkg = model.register(
        content_types=["application/json"],
        response_types=["application/json"],
        inference_instances=["ml.g5.xlarge", "ml.g5.2xlarge"],
        transform_instances=["ml.g5.xlarge"],
        model_package_group_name=args.model_package_group,
        approval_status=args.approval,
        model_metrics=model_metrics,
        description="CNN-LSTM trained on HyperPod (EKS)",
    )
    log.info("registered: %s (status=%s)", pkg.model_package_arn, args.approval)


if __name__ == "__main__":
    main()
