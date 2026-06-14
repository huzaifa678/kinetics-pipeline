"""Deploy the trained CNN-LSTM to a SageMaker real-time endpoint.

Uses the SageMaker Python SDK::

    python deploy/deploy_endpoint.py \
        --model-data s3://.../models/cnn-lstm/model.tar.gz \
        --role arn:aws:iam::<acct>:role/<sagemaker-exec-role> \
        --endpoint-name kinetics-cnn-lstm \
        --instance-type ml.g5.xlarge

Training happens on HyperPod (EKS); this is the inference/serving side on
SageMaker managed endpoints. `source_dir` ships both the handler and the
kinetics_trainer package so model_fn can rebuild the architecture.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import sagemaker
from sagemaker import ModelPackage
from sagemaker.pytorch import PyTorchModel

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(HERE, "..")  # ships inference/ + src/

sys.path.insert(0, os.path.join(HERE, "..", "src"))
from kinetics_trainer.observability import get_logger  # noqa: E402

log = get_logger("kinetics_deploy")


def latest_approved_package(sm: Any, group: str) -> str:
    resp = sm.list_model_packages(
        ModelPackageGroupName=group,
        ModelApprovalStatus="Approved",
        SortBy="CreationTime",
        SortOrder="Descending",
        MaxResults=1,
    )
    pkgs = resp.get("ModelPackageSummaryList", [])
    if not pkgs:
        raise SystemExit(f"no Approved model package in group {group!r}")
    return pkgs[0]["ModelPackageArn"]


def main() -> None:
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--model-data", help="s3://.../model.tar.gz (direct deploy)")
    src.add_argument(
        "--model-package-group", help="deploy the latest Approved version from this registry group"
    )
    ap.add_argument("--role", required=True, help="SageMaker execution role ARN")
    ap.add_argument("--endpoint-name", default="kinetics-cnn-lstm")
    ap.add_argument("--instance-type", default="ml.g5.xlarge")
    ap.add_argument("--instance-count", type=int, default=1)
    ap.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    ap.add_argument("--framework-version", default="2.3")
    ap.add_argument("--py-version", default="py311")
    ap.add_argument(
        "--serverless",
        action="store_true",
        help="deploy a serverless endpoint instead of a real-time instance",
    )
    args = ap.parse_args()

    session = sagemaker.Session(boto_session=_boto(args.region))

    if args.model_package_group:
        # Registry-driven deploy: take the latest Approved version.
        arn = latest_approved_package(session.sagemaker_client, args.model_package_group)
        log.info("deploying approved package: %s", arn)
        model = ModelPackage(role=args.role, model_package_arn=arn, sagemaker_session=session)
    else:
        model = PyTorchModel(
            model_data=args.model_data,
            role=args.role,
            entry_point="inference.py",
            source_dir=SOURCE_DIR,
            framework_version=args.framework_version,
            py_version=args.py_version,
            sagemaker_session=session,
            env={"SAGEMAKER_REQUIREMENTS": "requirements.txt"},
        )

    if args.serverless:
        from sagemaker.serverless import ServerlessInferenceConfig

        predictor = model.deploy(
            endpoint_name=args.endpoint_name,
            serverless_inference_config=ServerlessInferenceConfig(
                memory_size_in_mb=6144,
                max_concurrency=4,
            ),
        )
    else:
        predictor = model.deploy(
            initial_instance_count=args.instance_count,
            instance_type=args.instance_type,
            endpoint_name=args.endpoint_name,
        )
    log.info("deployed endpoint: %s", predictor.endpoint_name)


def _boto(region: str) -> Any:
    import boto3

    return boto3.Session(region_name=region)


if __name__ == "__main__":
    main()
