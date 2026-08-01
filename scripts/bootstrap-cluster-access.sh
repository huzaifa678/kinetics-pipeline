set -euo pipefail

# Fallback to manual apply

ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT="${PROJECT:-kinetics-pipeline}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Per-env Terragrunt units (values come from inputs — no tfvars/-var-file). The
# env is selected by directory: live/${ENVIRONMENT}/<layer>.
NET_LIVE="$ROOT/terraform/live/${ENVIRONMENT}/network"
INFRA_LIVE="$ROOT/terraform/live/${ENVIRONMENT}/infra"
CLUSTER_LIVE="$ROOT/terraform/live/${ENVIRONMENT}/cluster"

[ -d "$INFRA_LIVE" ] || { echo "::error:: missing Terragrunt unit $INFRA_LIVE (unknown env '$ENVIRONMENT'?)"; exit 1; }

echo "==> caller identity (must be a cluster admin in cluster_admin_principal_arns,"
echo "    e.g. arn:aws:iam::<acct>:user/terraform):"
aws sts get-caller-identity --query Arn --output text

echo
echo "==> phase 1/3: NETWORK layer (vpc/nat/subnets). AWS-API only, no VPN. Its own"
echo "    state — the infra layer below reads vpc_id/subnets/cidr from it, and the"
echo "    runner layer stands up from just this (bootstrap-runner.sh). Idempotent if"
echo "    the runner bootstrap already applied it."
# Env selected by directory; values come from Terragrunt inputs.
( cd "$NET_LIVE" && terragrunt init -input=false >/dev/null && terragrunt apply )

echo
echo "==> phase 2/3: INFRA layer (eks + tiered access entries, client_vpn, iam, ...)"
echo "    AWS-API only, no VPN needed. enable_hyperpod=false so this applies CLEAN —"
echo "    the SageMaker cluster can't create until ArgoCD (cluster layer) installs its"
echo "    deps chart (gotcha #1). Review the plan for stray destroys."
# -var beats the layer's Terragrunt input, forcing the cold-start hyperpod=false.
( cd "$INFRA_LIVE" && terragrunt init -input=false >/dev/null && terragrunt apply -var="enable_hyperpod=false" )

echo
echo "==> connect to the Client VPN now (SAML + split-DNS), in another shell:"
echo "      ./scripts/vpn-connect.sh"
echo "    The endpoint may take a few minutes to become 'available'. Continue only"
echo "    once 'kubectl get ns' succeeds — otherwise the cluster apply will time out."
read -r -p "Press Enter when the VPN is up and the cluster API is reachable... " _

echo
echo "==> phase 3/3: CLUSTER layer (ci-deployer RBAC + argocd; kubectl/helm → cluster)"
( cd "$CLUSTER_LIVE" && terragrunt init -input=false >/dev/null && terragrunt apply )

echo
echo "Done. tf-plan (viewer) + tf-apply (ci-deployers group) are authorized on the"
echo "cluster, and ArgoCD is bootstrapped."
echo
echo "NEXT: once ArgoCD shows the 'hyperpod-dependencies' Application Synced+Healthy,"
echo "bring HyperPod up (the layer's input enable_hyperpod defaults to true):"
echo "  ( cd $INFRA_LIVE && terragrunt apply )"
