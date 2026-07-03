#!/usr/bin/env bash
# One-shot setup of the GitHub Actions CI/CD config for this repo:
#   * repo variables (region, ECR repo, the 3 OIDC role ARNs, GitOps repo name)
#   * frontend-deploy vars (SPA bucket/distribution + role + VITE_* ) — only when
#     the frontend/cognito stack is applied (enable_frontend/enable_cognito)
#   * the GitHub Environment matching $ENVIRONMENT (used by the env-dispatch of
#     terraform-apply/plan) + `production` (used by frontend-deploy), gating the
#     prod-like ones with the repo owner as a required reviewer
#   * (optional) the GitHub App secrets for cross-repo GitOps pushes
#
# Values come from `terraform output` when the stack is applied; otherwise the
# roles/ECR are derived deterministically from ACCOUNT/REGION/PROJECT/ENVIRONMENT
# so you can set them before the first apply (they just won't exist until apply).
#
# IMPORTANT: run with ENVIRONMENT matching the env you applied — the role names
# are <project>-<environment>-gha-* (dev vs prod differ):
#   ENVIRONMENT=prod ./scripts/setup-github-ci.sh
#
# Requires: gh (authenticated), aws, terraform. Re-running is safe (idempotent).
#
# Usage:
#   ./scripts/setup-github-ci.sh
#   ENVIRONMENT=prod ./scripts/setup-github-ci.sh
#   GITOPS_APP_ID=123456 GITOPS_APP_PRIVATE_KEY_FILE=./app.pem ./scripts/setup-github-ci.sh
set -euo pipefail

REPO="${REPO:-huzaifa678/kinetics-pipeline}"
GITOPS_REPO_NAME="${GITOPS_REPO_NAME:-Kinetics-Continious-Delivery}"
PROJECT="${PROJECT:-kinetics-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:-kinetics-training}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform/bootstrap"

tfout() { terraform -chdir="$TF" output -raw "$1" 2>/dev/null || true; }
# Set a repo variable only when the value is non-empty (returns 0 either way).
set_var() { [ -n "${2:-}" ] || return 0; gh variable set "$1" --repo "$REPO" --body "$2"; echo "   set $1"; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
NAME="${PROJECT}-${ENVIRONMENT}"

# Prefer real outputs; fall back to deterministic construction.
ECR_REPOSITORY="$(tfout ecr_repository_url)"
[ -n "$ECR_REPOSITORY" ] || ECR_REPOSITORY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

ROLE_ECR="$(tfout gha_ecr_push_role_arn)"
[ -n "$ROLE_ECR" ] || ROLE_ECR="arn:aws:iam::${ACCOUNT_ID}:role/${NAME}-gha-ecr-push"
ROLE_PLAN="$(tfout gha_terraform_plan_role_arn)"
[ -n "$ROLE_PLAN" ] || ROLE_PLAN="arn:aws:iam::${ACCOUNT_ID}:role/${NAME}-gha-tf-plan"
ROLE_APPLY="$(tfout gha_terraform_apply_role_arn)"
[ -n "$ROLE_APPLY" ] || ROLE_APPLY="arn:aws:iam::${ACCOUNT_ID}:role/${NAME}-gha-tf-apply"

echo "==> Setting repo variables on $REPO"
gh variable set AWS_REGION       --repo "$REPO" --body "$REGION"
gh variable set ECR_REPOSITORY   --repo "$REPO" --body "$ECR_REPOSITORY"
gh variable set AWS_ROLE_ECR_PUSH --repo "$REPO" --body "$ROLE_ECR"
gh variable set AWS_ROLE_TF_PLAN --repo "$REPO" --body "$ROLE_PLAN"
gh variable set AWS_ROLE_TF_APPLY --repo "$REPO" --body "$ROLE_APPLY"
gh variable set GITOPS_REPO_NAME --repo "$REPO" --body "$GITOPS_REPO_NAME"


set_var AWS_ROLE_FRONTEND_DEPLOY "arn:aws:iam::${ACCOUNT_ID}:role/${NAME}-gha-frontend-deploy"

OWNER="${REPO%%/*}"
OWNER_ID="$(gh api "/users/${OWNER}" --jq .id)"

ensure_env() {
  local name="$1" gated="$2"
  local args=(-F "wait_timer=0")
  [ "$gated" = "1" ] && args+=(-F "reviewers[][type]=User" -F "reviewers[][id]=${OWNER_ID}")
  gh api -X PUT "/repos/${REPO}/environments/${name}" \
    -H "Accept: application/vnd.github+json" "${args[@]}" >/dev/null
  echo "   environment '${name}' ready$([ "$gated" = "1" ] && echo " (reviewer: ${OWNER})")"
}

echo "==> Ensuring GitHub Environments"
case "$ENVIRONMENT" in
  prod | production) ensure_env "$ENVIRONMENT" 1 ;;
  *) ensure_env "$ENVIRONMENT" 0 ;;
esac
# frontend-deploy.yml always runs under `production` — keep it gated.
[ "$ENVIRONMENT" = "production" ] || ensure_env production 1

if [ -n "${GITOPS_APP_ID:-}" ] && [ -n "${GITOPS_APP_PRIVATE_KEY_FILE:-}" ]; then
  echo "==> Setting GitHub App secrets"
  KEY_FILE="$(ls -1t $GITOPS_APP_PRIVATE_KEY_FILE 2>/dev/null | head -1)"
  : "${KEY_FILE:?private key not found at: $GITOPS_APP_PRIVATE_KEY_FILE}"
  gh secret set GITOPS_APP_ID --repo "$REPO" --body "$GITOPS_APP_ID"
  gh secret set GITOPS_APP_PRIVATE_KEY --repo "$REPO" < "$KEY_FILE"
else
  echo "==> SKIP GitHub App secrets (set GITOPS_APP_ID + GITOPS_APP_PRIVATE_KEY_FILE to add them)"
fi

echo
echo "Done. Current variables:"
gh variable list --repo "$REPO"
