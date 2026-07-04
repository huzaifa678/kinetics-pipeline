set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT="${PROJECT:-kinetics-pipeline}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
NAME="${PROJECT}-${ENVIRONMENT}"
SECRET_ID="${NAME}-gha-runner-pat"
ASG="${NAME}-gha-runner"

: "${RUNNER_PAT:?set RUNNER_PAT to a GitHub token with repo Administration read/write}"

echo "==> 1/3 apply runner module (profile: $ENVIRONMENT)"
terraform -chdir="$TF" apply \
  -var-file="terraform.tfvars.${ENVIRONMENT}" \
  -target=module.github_runner -auto-approve -input=false

echo "==> 2/3 store the PAT in Secrets Manager ($SECRET_ID)"
aws secretsmanager put-secret-value --region "$REGION" \
  --secret-id "$SECRET_ID" --secret-string "$RUNNER_PAT" >/dev/null
echo "   stored."

echo "==> 3/3 cycle the ASG instance so user-data re-runs with the PAT present"
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
