#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform/infra"
PREFIX="${PREFIX:-kinetics400}"
# Persistent dataset bucket, OUTSIDE the Terraform stack (survives destroy/teardown).
ARCHIVE_BUCKET="${ARCHIVE_BUCKET:-kinetics-pipeline-archive}"
cmd="${1:-sync}"

command -v aws >/dev/null || { echo "aws CLI required"; exit 1; }

resolve_data_bucket() {
  [ -n "${DATA_BUCKET:-}" ] && { echo "$DATA_BUCKET"; return; }
  terraform -chdir="$TF_DIR" output -raw data_bucket 2>/dev/null || true
}

case "$cmd" in
  upload)
    : "${LOCAL_DIR:?set LOCAL_DIR=<local kinetics400/ tree (class-foldered mp4s)>}"
    [ -d "$LOCAL_DIR" ] || { echo "LOCAL_DIR not a directory: $LOCAL_DIR"; exit 1; }
    echo "==> uploading $LOCAL_DIR  ->  s3://$ARCHIVE_BUCKET/$PREFIX/"
    aws s3 sync "$LOCAL_DIR" "s3://$ARCHIVE_BUCKET/$PREFIX/" --only-show-errors
    echo "==> archive populated."
    ;;
  sync)
    DATA_BUCKET="$(resolve_data_bucket)"
    : "${DATA_BUCKET:?could not resolve data bucket — apply terraform first or set DATA_BUCKET}"
    echo "==> syncing s3://$ARCHIVE_BUCKET/$PREFIX/  ->  s3://$DATA_BUCKET/$PREFIX/"
    aws s3 sync "s3://$ARCHIVE_BUCKET/$PREFIX/" "s3://$DATA_BUCKET/$PREFIX/" --only-show-errors
    echo "==> done. FSx auto-imports new/changed objects under /data/$PREFIX (lazy-loaded on first read)."
    ;;
  *)
    echo "usage: ARCHIVE_BUCKET=<bucket> $0 [upload|sync]"; exit 1 ;;
esac
