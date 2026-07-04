set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT="${PROJECT:-kinetics-pipeline}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
VARFILE="terraform.tfvars.${ENVIRONMENT}"

[ -f "$TF/$VARFILE" ] || { echo "::error:: missing $TF/$VARFILE"; exit 1; }

echo "==> caller identity (must be a cluster admin listed in cluster_admin_principal_arns,"
echo "    e.g. arn:aws:iam::<acct>:user/terraform — and you must be ON THE VPN):"
aws sts get-caller-identity --query Arn --output text

echo
echo "==> apply cluster-access bootstrap (profile: $ENVIRONMENT)"
echo "    targets: module.ci_deployer_rbac, module.eks"
echo "    (review the plan — a stray 'destroy' here is worth catching before you approve)"
terraform -chdir="$TF" apply \
  -var-file="$VARFILE" \
  -target=module.ci_deployer_rbac \
  -target=module.eks

echo
echo "Done. tf-plan (viewer) + tf-apply (ci-deployers group) are now authorized on"
echo "the cluster. Re-run the CI pipeline / the main terraform apply."
