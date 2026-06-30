set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform"
CD_REPO="${CD_REPO:-$(cd "$ROOT/.." && pwd)/Kinetics-CD}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

KPS_VALUES="$CD_REPO/gitops/environments/${ENVIRONMENT}/values/kube-prometheus-stack.yaml"
INF_VALUES="$CD_REPO/helm/inference-service/values.yaml"

command -v yq >/dev/null || { echo "ERROR: yq (v4) is required" >&2; exit 1; }
[ -d "$CD_REPO" ] || { echo "ERROR: CD repo not found at $CD_REPO (set CD_REPO=)" >&2; exit 1; }

# Print the value of a terraform output, or empty if unset/null/no-state.
# Uses -json so terraform's "No outputs found" warning can't leak into the value.
tfout() {
  local j
  j="$(terraform -chdir="$TF" output -json "$1" 2>/dev/null)" || return 0
  [ -z "$j" ] || [ "$j" = "null" ] && return 0
  # Strip the surrounding quotes of the JSON string scalar.
  printf '%s' "$j" | sed -e 's/^"//' -e 's/"$//'
}

changed=0

AMP_URL="$(tfout amp_remote_write_url)"
if [ -n "$AMP_URL" ]; then
  [ -f "$KPS_VALUES" ] || { echo "ERROR: $KPS_VALUES missing" >&2; exit 1; }
  echo "==> kube-prometheus-stack: remoteWrite url = $AMP_URL"
  AMP_URL="$AMP_URL" yq -i '.prometheus.prometheusSpec.remoteWrite[0].url = strenv(AMP_URL)
    | .prometheus.prometheusSpec.remoteWrite[0].sigv4.region = "us-east-1"' "$KPS_VALUES"
  changed=1
else
  echo "==> AMP disabled (no amp_remote_write_url) — skipping kube-prometheus-stack"
fi

# --- Inference endpoint ---------------------------------------------------
# Prod: public api host + WAF + Swagger off + CORS + Cognito JWT.
# Dev:  internal ALB at inference_host, docs on, no auth.
API_HOST="$(tfout inference_api_host)"
INF_HOST="$(tfout inference_host)"
if [ -n "$API_HOST" ]; then
  [ -f "$INF_VALUES" ] || { echo "ERROR: $INF_VALUES missing" >&2; exit 1; }
  WAF_ARN="$(tfout inference_api_waf_arn)"
  SPA_URL="$(tfout spa_url)"
  COG_ISSUER="$(tfout cognito_issuer)"
  AUDIENCE="$(tfout cognito_spa_client_id),$(tfout cognito_machine_client_id)"
  echo "==> inference-service: PROD public ingress at $API_HOST (WAF + Cognito, docs off)"
  H="$API_HOST" W="$WAF_ARN" C="$SPA_URL" I="$COG_ISSUER" A="$AUDIENCE" yq -i '
    .ingress.enabled = true
    | .ingress.scheme = "internet-facing"
    | .ingress.host = strenv(H)
    | .ingress.wafAclArn = strenv(W)
    | .app.enableDocs = "false"
    | .app.corsAllowOrigins = strenv(C)
    | .app.cognito.issuer = strenv(I)
    | .app.cognito.audience = strenv(A)' "$INF_VALUES"
  changed=1
elif [ -n "$INF_HOST" ]; then
  [ -f "$INF_VALUES" ] || { echo "ERROR: $INF_VALUES missing" >&2; exit 1; }
  echo "==> inference-service: internal ingress.enabled=true host=$INF_HOST"
  INF_HOST="$INF_HOST" yq -i '.ingress.enabled = true
    | .ingress.scheme = "internal"
    | .ingress.host = strenv(INF_HOST)' "$INF_VALUES"
  changed=1
else
  echo "==> No inference domain set — leaving inference ingress disabled"
fi

if [ "$changed" = 0 ]; then
  echo "Nothing to sync."
  exit 0
fi

echo ""
echo "==> Diff in $CD_REPO:"
git -C "$CD_REPO" --no-pager diff -- \
  "gitops/environments/${ENVIRONMENT}/values/kube-prometheus-stack.yaml" \
  "helm/inference-service/values.yaml" || true

if [ "${COMMIT:-0}" = "1" ]; then
  git -C "$CD_REPO" add \
    "gitops/environments/${ENVIRONMENT}/values/kube-prometheus-stack.yaml" \
    "helm/inference-service/values.yaml"
  git -C "$CD_REPO" commit -m "chore(sync): terraform outputs -> AMP url + inference ingress" || true
  [ "${PUSH:-0}" = "1" ] && git -C "$CD_REPO" push
  echo "==> Committed${PUSH:+ and pushed}."
else
  echo ""
  echo "Review the diff above, then commit in $CD_REPO (or re-run with COMMIT=1 [PUSH=1])."
fi
