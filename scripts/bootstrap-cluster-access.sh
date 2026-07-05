set -euo pipefail

# Two-layer bootstrap (see terraform/infra + terraform/cluster). No -target: each
# layer is a clean, standalone `terraform apply`. Phase 1 is AWS-API only (incl.
# the Client VPN) and needs no cluster reach. You then connect the VPN. Phase 2 is
# the CLUSTER layer (kubernetes/helm/kubectl) and needs the VPN — its FIRST apply
# must run as a cluster admin (k8s escalation-prevention on the ci-deployer RBAC).

ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT="${PROJECT:-kinetics-pipeline}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA="$ROOT/terraform/infra"
CLUSTER="$ROOT/terraform/cluster"
VARFILE="terraform.tfvars.${ENVIRONMENT}"

[ -f "$INFRA/$VARFILE" ] || { echo "::error:: missing $INFRA/$VARFILE"; exit 1; }

echo "==> caller identity (must be a cluster admin in cluster_admin_principal_arns,"
echo "    e.g. arn:aws:iam::<acct>:user/terraform):"
aws sts get-caller-identity --query Arn --output text

echo
echo "==> phase 1/2: INFRA layer (vpc, eks + tiered access entries, client_vpn, ...)"
echo "    AWS-API only, no VPN needed. enable_hyperpod=false so this applies CLEAN —"
echo "    the SageMaker cluster can't create until ArgoCD (cluster layer) installs its"
echo "    deps chart (gotcha #1). Review the plan for stray destroys."
terraform -chdir="$INFRA" init -input=false >/dev/null
terraform -chdir="$INFRA" apply -var-file="$VARFILE" -var="enable_hyperpod=false"

echo
echo "==> connect to the Client VPN now (SAML + split-DNS), in another shell:"
echo "      ./scripts/vpn-connect.sh"
echo "    The endpoint may take a few minutes to become 'available'. Continue only"
echo "    once 'kubectl get ns' succeeds — otherwise the cluster apply will time out."
read -r -p "Press Enter when the VPN is up and the cluster API is reachable... " _

echo
echo "==> phase 2/2: CLUSTER layer (ci-deployer RBAC + argocd; kubectl/helm → cluster)"
cvar=""; [ -f "$CLUSTER/$VARFILE" ] && cvar="-var-file=$VARFILE"
terraform -chdir="$CLUSTER" init -input=false >/dev/null
terraform -chdir="$CLUSTER" apply $cvar

echo
echo "Done. tf-plan (viewer) + tf-apply (ci-deployers group) are authorized on the"
echo "cluster, and ArgoCD is bootstrapped."
echo
echo "NEXT: once ArgoCD shows the 'hyperpod-dependencies' Application Synced+Healthy,"
echo "bring HyperPod up (default enable_hyperpod=true):"
echo "  terraform -chdir=$INFRA apply -var-file=$VARFILE"
