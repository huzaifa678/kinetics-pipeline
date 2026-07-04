"""
Auto-stop guard for the HyperPod GPU instance group.

Runs on an EventBridge schedule. If average GPU utilization across the cluster
has been below the idle threshold for the lookback window, it scales the GPU
instance group to 0 so you stop paying for idle accelerators.

This is intentionally conservative: it only ever scales DOWN. Scaling up for a
run is a deliberate human/CI action (see the repo README).
"""
import os
import datetime

import boto3

IDLE_GPU_UTIL_PCT = float(os.environ.get("IDLE_GPU_UTIL_PCT", "5"))
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "30"))
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
GPU_INSTANCE_GROUP = os.environ["GPU_INSTANCE_GROUP"]
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")

sagemaker = boto3.client("sagemaker")
cloudwatch = boto3.client("cloudwatch")
sns = boto3.client("sns")


def _current_count():
    desc = sagemaker.describe_cluster(ClusterName=CLUSTER_NAME)
    for group in desc.get("InstanceGroups", []):
        if group["InstanceGroupName"] == GPU_INSTANCE_GROUP:
            return group, desc
    raise RuntimeError(f"Instance group {GPU_INSTANCE_GROUP} not found")


def _avg_gpu_util():
    """Average GPU utilization over the idle window, via the DCGM CloudWatch metric."""
    end = datetime.datetime.utcnow()
    start = end - datetime.timedelta(minutes=IDLE_MINUTES)
    resp = cloudwatch.get_metric_statistics(
        Namespace="ContainerInsights",
        MetricName="DCGM_FI_DEV_GPU_UTIL",
        Dimensions=[{"Name": "ClusterName", "Value": CLUSTER_NAME}],
        StartTime=start,
        EndTime=end,
        Period=300,
        Statistics=["Average"],
    )
    points = resp.get("Datapoints", [])
    if not points:
        # No metric data usually means no GPU workload reporting -> treat as idle.
        return 0.0
    return sum(p["Average"] for p in points) / len(points)


def _notify(message):
    if SNS_TOPIC_ARN:
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject="HyperPod auto-stop", Message=message)


def handler(event, context):
    group, desc = _current_count()
    count = group["CurrentCount"]

    if count == 0:
        return {"status": "already_zero"}

    util = _avg_gpu_util()
    if util > IDLE_GPU_UTIL_PCT:
        return {"status": "busy", "gpu_util": util}

    # Idle: scale the GPU group to 0.
    instance_groups = [
        {
            "InstanceGroupName": g["InstanceGroupName"],
            "InstanceType": g["InstanceType"],
            "InstanceCount": 0 if g["InstanceGroupName"] == GPU_INSTANCE_GROUP else g["CurrentCount"],
            "ExecutionRole": g["ExecutionRole"],
            "LifeCycleConfig": g["LifeCycleConfig"],
        }
        for g in desc["InstanceGroups"]
    ]
    sagemaker.update_cluster(ClusterName=CLUSTER_NAME, InstanceGroups=instance_groups)

    msg = (
        f"Scaled GPU group '{GPU_INSTANCE_GROUP}' from {count} to 0 "
        f"(avg GPU util {util:.1f}% over {IDLE_MINUTES}m)."
    )
    _notify(msg)
    return {"status": "scaled_to_zero", "previous_count": count, "gpu_util": util}
