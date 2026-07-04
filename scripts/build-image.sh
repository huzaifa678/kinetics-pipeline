#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${PLATFORM:-linux/amd64}"
REGION="${REGION:-us-east-1}"
TAG="${TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo latest)}"

# Local image name when no registry is configured (terraform not applied yet).
LOCAL_IMAGE="${LOCAL_IMAGE:-kinetics-training}"

if [ -z "${ECR_REPOSITORY:-}" ]; then
  ECR_REPOSITORY="$(terraform -chdir="$ROOT/terraform/infra" output -raw ecr_repository_url 2>/dev/null || true)"
fi

if [ "${PUSH:-0}" = "1" ]; then
  # Pushing requires a real registry.
  : "${ECR_REPOSITORY:?set ECR_REPOSITORY=<acct>.dkr.ecr.<region>.amazonaws.com/kinetics-training (or apply terraform first)}"
  IMAGE="${ECR_REPOSITORY}:${TAG}"
else
  # Local build: fall back to a bare image name if no registry is set.
  IMAGE="${ECR_REPOSITORY:-$LOCAL_IMAGE}:${TAG}"
fi
echo "==> Building ${IMAGE} for ${PLATFORM}"

# Ensure a buildx builder exists (qemu enables amd64 emulation on arm64 hosts).
docker buildx inspect kinetics >/dev/null 2>&1 || docker buildx create --name kinetics --use >/dev/null
docker buildx use kinetics

OUTPUT="--load" # default: load the single-arch image into the local docker
if [ "${PUSH:-0}" = "1" ]; then
  OUTPUT="--push"
  REGISTRY="${ECR_REPOSITORY%%/*}"
  echo "==> Logging in to ${REGISTRY}"
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
fi

docker buildx build \
  --platform "$PLATFORM" \
  --tag "$IMAGE" \
  $OUTPUT \
  "$ROOT/training"

echo "==> Done: ${IMAGE}"
[ "${PUSH:-0}" = "1" ] && echo "Pushed. Bump the GitOps image tag to: ${TAG}"
