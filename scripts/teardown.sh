#!/usr/bin/env bash

set -euo pipefail

# Env selected by directory: live/${ENVIRONMENT}/<layer>. Values come from
# Terragrunt inputs (no tfvars/-var-file). Defaults to dev.
ENVIRONMENT="${ENVIRONMENT:-dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE="$ROOT/terraform/live/${ENVIRONMENT}"
INFRA_LIVE="$LIVE/infra"
CLUSTER_LIVE="$LIVE/cluster"
RUNNER_LIVE="$LIVE/runner"
NETWORK_LIVE="$LIVE/network"
ECR_REPO_NAME="${ECR_REPO_NAME:-kinetics-training}"
tf() { ( cd "$INFRA_LIVE" && terragrunt "$@" ); }
tfc() { ( cd "$CLUSTER_LIVE" && terragrunt "$@" ); }
tfr() { ( cd "$RUNNER_LIVE" && terragrunt "$@" ); }
tfn() { ( cd "$NETWORK_LIVE" && terragrunt "$@" ); }

command -v terragrunt >/dev/null || { echo "terragrunt required"; exit 1; }
command -v terraform  >/dev/null || { echo "terraform required"; exit 1; }
command -v aws        >/dev/null || { echo "aws CLI required"; exit 1; }
command -v python3    >/dev/null || { echo "python3 required"; exit 1; }
[ -d "$INFRA_LIVE" ] || { echo "missing Terragrunt unit $INFRA_LIVE (unknown env '$ENVIRONMENT'?)"; exit 1; }

echo "==> Teardown: env '$ENVIRONMENT' ($INFRA_LIVE and sibling layers)"
if [ "${AUTO_APPROVE:-0}" != "1" ]; then
  echo "    This EMPTIES all S3 buckets in state and DESTROYS the stack — irreversible."
  read -rp "    Type 'destroy' to continue: " ans
  [ "$ans" = "destroy" ] || { echo "aborted"; exit 1; }
fi

echo "==> [0/6] Destroy the CLUSTER layer first (in-cluster: argocd, RBAC, addons)"
if [ -d "$CLUSTER_LIVE" ]; then
  tfc destroy -auto-approve || {
    echo "    cluster destroy failed (on the VPN? cluster already gone?)."
    echo "    If the layer is empty/irrelevant, continue; otherwise fix and re-run."
  }
fi

echo "==> [1/6] Karpenter node check"
if command -v kubectl >/dev/null && kubectl get nodes >/dev/null 2>&1; then
  if kubectl get nodeclaims >/dev/null 2>&1; then
    n="$(kubectl get nodeclaims --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" != "0" ]; then
      echo "    deleting $n NodeClaim(s) so Karpenter deprovisions their nodes"
      kubectl delete nodeclaims --all --wait=true || true
    else
      echo "    no NodeClaims — nothing Karpenter-launched to drain"
    fi
  fi
else
  echo "    kubectl not reachable — SKIPPING. Verify by hand that Karpenter left no"
  echo "    GPU/CPU nodes running (EC2 console); destroy will not remove them."
fi

echo "==> [2/6] Emptying S3 buckets"
tf init -input=false >/dev/null 2>&1 || true
buckets="$(tf state pull | python3 -c '
import sys, json
s = json.load(sys.stdin)
for r in s.get("resources", []):
    if r.get("type") == "aws_s3_bucket":
        for inst in r.get("instances", []):
            b = inst.get("attributes", {}).get("bucket")
            if b: print(b)
')"
for b in $buckets; do
  if ! aws s3api head-bucket --bucket "$b" 2>/dev/null; then
    echo "    skip $b (already gone)"; continue
  fi
  echo "    emptying s3://$b"
  aws s3 rm "s3://$b" --recursive --only-show-errors || true
  # Versioned buckets keep old versions + delete markers; purge them or the
  # bucket won't delete. aws cli auto-paginates list-object-versions.
  aws s3api list-object-versions --bucket "$b" --output json 2>/dev/null | python3 -c '
import sys, json, subprocess
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
items = (d.get("Versions") or []) + (d.get("DeleteMarkers") or [])
for it in items:
    subprocess.run(["aws","s3api","delete-object","--bucket",sys.argv[1],
                    "--key",it["Key"],"--version-id",it["VersionId"]], check=False)
' "$b"
done

echo "==> [3/6] ECR repo"
if [ "${DELETE_ECR:-0}" = "1" ]; then
  echo "    DELETE_ECR=1 — deleting repo '$ECR_REPO_NAME' and its images"
  aws ecr delete-repository --repository-name "$ECR_REPO_NAME" --force >/dev/null 2>&1 || true
fi
if tf state list 2>/dev/null | grep -q '^module\.ecr\.aws_ecr_repository\.training$'; then
  echo "    dropping module.ecr.aws_ecr_repository.training from state (prevent_destroy)"
  tf state rm module.ecr.aws_ecr_repository.training >/dev/null
fi

echo "==> [4/6] terragrunt destroy (INFRA layer: eks, iam, hyperpod, msk, ...)"
tf destroy -auto-approve

echo "==> [5/6] Destroy the RUNNER layer (its ASG/ENIs sit in the network subnets,"
echo "          so it must go before the network destroy)"
if [ -d "$RUNNER_LIVE" ]; then
  tfr init -input=false >/dev/null 2>&1 || true
  tfr destroy -auto-approve || {
    echo "    runner destroy failed (layer empty/never applied?). Continuing."
  }
fi

echo "==> [6/6] Destroy the NETWORK layer (vpc/nat/subnets) LAST"
# The VPC lives in its own layer (terraform/network); infra + runner both read it
# via remote_state, so it's destroyed after both are gone.
tfn init -input=false >/dev/null 2>&1 || true
tfn destroy -auto-approve

echo "==> Done."
[ "${DELETE_ECR:-0}" = "1" ] || echo "    Note: ECR repo '$ECR_REPO_NAME' was left intact in AWS (run with DELETE_ECR=1 to remove)."
