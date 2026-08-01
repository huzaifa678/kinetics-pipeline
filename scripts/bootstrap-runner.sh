set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT="${PROJECT:-kinetics-pipeline}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Per-env Terragrunt units (values come from inputs — no tfvars/-var-file).
NET_LIVE="$ROOT/terraform/live/${ENVIRONMENT}/network"
RUNNER_LIVE="$ROOT/terraform/live/${ENVIRONMENT}/runner"
NAME="${PROJECT}-${ENVIRONMENT}"
SECRET_ID="${NAME}-gha-runner-pat"
ASG="${NAME}-gha-runner"

: "${RUNNER_PAT:?set RUNNER_PAT to a GitHub token with repo Administration read/write}"

echo "==> 1/4 ensure the NETWORK layer (vpc) exists — the runner reads it"
# Env is selected by directory (live/${ENVIRONMENT}); values come from inputs.
( cd "$NET_LIVE" && terragrunt init -input=false >/dev/null && terragrunt apply -auto-approve -input=false )

echo "==> 2/4 apply the runner layer (name/vpc from the network remote_state)"
( cd "$RUNNER_LIVE" && terragrunt init -input=false >/dev/null && terragrunt apply -auto-approve -input=false )

echo "==> 3/4 store the PAT in Secrets Manager ($SECRET_ID)"
aws secretsmanager put-secret-value --region "$REGION" \
  --secret-id "$SECRET_ID" --secret-string "$RUNNER_PAT" >/dev/null
echo "   stored."

echo "==> 4/4 cycle the ASG instance so user-data re-runs with the PAT present"
IID="$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
  --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text 2>/dev/null || echo None)"
if [ "$IID" != "None" ] && [ -n "$IID" ]; then
  aws autoscaling terminate-instance-in-auto-scaling-group --region "$REGION" \
    --instance-id "$IID" --no-should-decrement-desired-capacity >/dev/null
  echo "   terminated $IID; the ASG will relaunch and register."
else
  echo "   no instance yet; the ASG will launch and register a new runner."
fi

echo
echo "Done, the runner should be registered in GitHub shortly."
echo "(2-3 minutes required)."
