#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-kinetics-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

if [ -z "${DATA_BUCKET:-}" ]; then
  DATA_BUCKET="$(terraform -chdir="$ROOT/terraform/infra" output -raw data_bucket 2>/dev/null || true)"
fi
if [ -z "${DATA_BUCKET:-}" ] && command -v aws >/dev/null; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  [ -n "$ACCOUNT_ID" ] && DATA_BUCKET="${PROJECT}-${ENVIRONMENT}-data-${ACCOUNT_ID}"
fi
: "${DATA_BUCKET:?could not resolve DATA_BUCKET — set it explicitly or apply terraform first}"

REMOTE_URL="s3://${DATA_BUCKET}/dvcstore"
echo "Using DVC remote: ${REMOTE_URL}"

command -v dvc >/dev/null || { echo "dvc not installed: pip install 'dvc[s3]'"; exit 1; }

[ -d .dvc ] || dvc init
dvc remote add -d -f s3store "$REMOTE_URL"

dvc add data/manifests/train.csv data/manifests/val.csv data/manifests/dataset_version.json

echo
echo "Next:"
echo "  git add data/manifests/*.dvc data/.gitignore .dvc/config"
echo "  git commit -m 'data: version kinetics manifests with dvc'"
echo "  dvc push                      # uploads manifests to ${REMOTE_URL}"
echo
echo "Reproduce a past dataset later:  git checkout <commit> && dvc pull"
