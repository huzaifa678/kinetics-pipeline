#!/usr/bin/env bash
# Scale the HyperPod GPU instance group up (to run training) or down (to stop
# paying). This is the deliberate human action that starts a run; the
# auto-stop Lambda handles scaling back to 0 if you forget.
#
# Usage:
#   ./scale-gpus.sh up 2      # 2 GPU nodes
#   ./scale-gpus.sh down      # scale to 0
set -euo pipefail

REGION="${REGION:-us-east-1}"
CLUSTER="${CLUSTER:-kinetics-pipeline-dev}"
GROUP="${GROUP:-gpu-training}"

ACTION="${1:?usage: scale-gpus.sh up|down [count]}"
COUNT="${2:-0}"
[[ "$ACTION" == "down" ]] && COUNT=0

# Read the current group config and re-submit it with the new count.
GROUPS=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER" --region "$REGION" \
  --query 'InstanceGroups' --output json)

NEW_GROUPS=$(echo "$GROUPS" | python3 -c "
import json,sys
groups=json.load(sys.stdin)
out=[]
for g in groups:
    count=$COUNT if g['InstanceGroupName']=='$GROUP' else g['CurrentCount']
    out.append({
        'InstanceGroupName': g['InstanceGroupName'],
        'InstanceType': g['InstanceType'],
        'InstanceCount': count,
        'ExecutionRole': g['ExecutionRole'],
        'LifeCycleConfig': g['LifeCycleConfig'],
        'ThreadsPerCore': g.get('ThreadsPerCore', 1),
    })
print(json.dumps(out))
")

aws sagemaker update-cluster \
  --cluster-name "$CLUSTER" --region "$REGION" \
  --instance-groups "$NEW_GROUPS"

echo "Requested $GROUP -> $COUNT node(s) on $CLUSTER."
