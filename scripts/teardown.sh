#!/usr/bin/env bash

set -euo pipefail

# Env selected by directory: live/${ENVIRONMENT}/<layer>. Values come from
# Terragrunt inputs (no tfvars/-var-file). Defaults to dev.
ENVIRONMENT="${ENVIRONMENT:-prod}"
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

echo "==> [0/7] Destroy the CLUSTER layer first (in-cluster: argocd, RBAC, addons)"
# ArgoCD Applications carry the resources-finalizer.argocd.argoproj.io finalizer;
# deleting them (as the argocd-apps Helm uninstall does) blocks until the argocd
# application-controller processes it. If that controller is down/starved (e.g.
# node DiskPressure), the finalizer never clears and the Helm uninstall dies with
# "context deadline exceeded". Strip the finalizers first so the release uninstalls
# cleanly — we're destroying the whole cluster next, so per-app pruning is moot.
if command -v kubectl >/dev/null && kubectl get ns argocd >/dev/null 2>&1; then
  echo "    stripping ArgoCD Application finalizers (avoid uninstall deadlock)"
  kubectl -n argocd patch applications.argoproj.io --all --type=merge \
    -p '{"metadata":{"finalizers":[]}}' --request-timeout=30s 2>/dev/null || true
fi
if [ -d "$CLUSTER_LIVE" ]; then
  tfc destroy -auto-approve || {
    echo "    cluster destroy failed (on the VPN? cluster already gone?)."
    echo "    If the layer is empty/irrelevant, continue; otherwise fix and re-run."
  }
fi

echo "==> [1/7] Karpenter node check"
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

echo "==> [2/7] Emptying S3 buckets"
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

echo "==> [3/7] ECR repo"
if [ "${DELETE_ECR:-0}" = "1" ]; then
  echo "    DELETE_ECR=1 — deleting repo '$ECR_REPO_NAME' and its images"
  aws ecr delete-repository --repository-name "$ECR_REPO_NAME" --force >/dev/null 2>&1 || true
fi
if tf state list 2>/dev/null | grep -q '^module\.ecr\.aws_ecr_repository\.training$'; then
  echo "    dropping module.ecr.aws_ecr_repository.training from state (prevent_destroy)"
  tf state rm module.ecr.aws_ecr_repository.training >/dev/null
fi

echo "==> [4/7] terragrunt destroy (INFRA layer: eks, iam, hyperpod, msk, ...)"
# Pre-destroy unblockers so the infra layer can actually delete:
#  (a) RDS deletion protection blocks DeleteDBInstance (the backstage Postgres sets
#      deletion_protection=true). Disable it on protected kinetics* DBs first.
for db in $(aws rds describe-db-instances \
    --query "DBInstances[?DeletionProtection==\`true\` && starts_with(DBInstanceIdentifier, \`kinetics\`)].DBInstanceIdentifier" \
    --output text 2>/dev/null || true); do
  echo "    disabling deletion protection on RDS $db"
  aws rds modify-db-instance --db-instance-identifier "$db" \
    --no-deletion-protection --apply-immediately >/dev/null 2>&1 || true
done
#  (b) Detached (status=available) ENIs — e.g. VPC-CNI "aws-K8S-i-*" interfaces left
#      by terminated EKS/Karpenter nodes — keep the node shared SG alive, so its
#      DeleteSecurityGroup fails with DependencyViolation. Sweep them from the VPC.
#      (Live LB ENIs are "in-use", not "available", so they're untouched here and
#      are cleaned in [6/7] after the controller is gone.)
tfn init -input=false >/dev/null 2>&1 || true
DESTROY_VPC="$( ( cd "$NETWORK_LIVE" && terragrunt output -raw vpc_id ) 2>/dev/null || true )"
if [ -z "${DESTROY_VPC:-}" ] || [ "$DESTROY_VPC" = "None" ]; then
  DESTROY_VPC="$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=*${ENVIRONMENT}*" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
fi
if [ -n "${DESTROY_VPC:-}" ] && [ "$DESTROY_VPC" != "None" ]; then
  for eni in $(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$DESTROY_VPC" "Name=status,Values=available" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true); do
    echo "    deleting orphaned (available) ENI $eni"
    aws ec2 delete-network-interface --network-interface-id "$eni" || true
  done
fi
tf destroy -auto-approve

echo "==> [5/7] Destroy the RUNNER layer (its ASG/ENIs sit in the network subnets,"
echo "          so it must go before the network destroy)"
if [ -d "$RUNNER_LIVE" ]; then
  tfr init -input=false >/dev/null 2>&1 || true
  tfr destroy -auto-approve || {
    echo "    runner destroy failed (layer empty/never applied?). Continuing."
  }
fi

echo "==> [6/7] Delete k8s-managed NLB/ALB + leftover ENIs (they block the VPC destroy)"
# The AWS Load Balancer Controller creates NLBs/ALBs — plus their ENIs and
# frontend security groups — from in-cluster Ingress/Service objects (ingress-nginx
# NLB, inference ALB, ...). Terraform does NOT manage these, so once EKS is gone
# they orphan and the NETWORK destroy below fails with DependencyViolation
# (subnets/SGs still in use). EKS was destroyed in [4], so the controller is gone
# and cannot recreate them — safe to delete via the AWS API here.
tfn init -input=false >/dev/null 2>&1 || true
VPC_ID="$( ( cd "$NETWORK_LIVE" && terragrunt output -raw vpc_id ) 2>/dev/null || true )"
if [ -z "${VPC_ID:-}" ] || [ "$VPC_ID" = "None" ]; then
  VPC_ID="$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*${ENVIRONMENT}*" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
fi
if [ -z "${VPC_ID:-}" ] || [ "$VPC_ID" = "None" ]; then
  echo "    could not resolve the VPC id — SKIPPING (network may already be gone)."
else
  echo "    target VPC: $VPC_ID"
  # 1) Delete every controller-created ELBv2 (NLB + ALB) in this VPC. The
  #    elbv2.k8s.aws/cluster tag marks LB-controller ownership; never touch a
  #    load balancer without it (defensive against any future TF-managed LB).
  for arn in $(aws elbv2 describe-load-balancers \
      --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true); do
    owner="$(aws elbv2 describe-tags --resource-arns "$arn" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" \
      --output text 2>/dev/null || echo None)"
    if [ -n "$owner" ] && [ "$owner" != "None" ]; then
      echo "    deleting k8s load balancer ($owner): $arn"
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" || true
    else
      echo "    skipping non-k8s load balancer: $arn"
    fi
  done
  # 2) LB deletion is async — wait for its ENIs (description "ELB ...") to detach.
  echo "    waiting up to 180s for load-balancer ENIs to release…"
  for _ in $(seq 1 18); do
    remaining="$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB *" \
      --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 0)"
    [ "${remaining:-0}" = "0" ] && break
    sleep 10
  done
  # 3) Delete any leftover *available* (detached) ELB ENIs still lingering.
  for eni in $(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" "Name=description,Values=ELB *" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true); do
    echo "    deleting leftover ENI $eni"
    aws ec2 delete-network-interface --network-interface-id "$eni" || true
  done
  # 4) Delete orphaned LB-controller frontend security groups (they reference /
  #    are referenced by the node SG and would block the SG teardown otherwise).
  for sg in $(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag-key,Values=elbv2.k8s.aws/cluster" \
      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true); do
    echo "    deleting orphaned LB security group $sg"
    aws ec2 delete-security-group --group-id "$sg" || true
  done
fi

echo "==> [7/7] Destroy the NETWORK layer (vpc/nat/subnets) LAST"
# The VPC lives in its own layer (terraform/network); infra + runner both read it
# via remote_state, so it's destroyed after both are gone.
tfn init -input=false >/dev/null 2>&1 || true
tfn destroy -auto-approve

echo "==> Done."
[ "${DELETE_ECR:-0}" = "1" ] || echo "    Note: ECR repo '$ECR_REPO_NAME' was left intact in AWS (run with DELETE_ECR=1 to remove)."
