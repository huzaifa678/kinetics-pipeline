.PHONY: tf-init tf-validate tf-plan validate-manifests validate lint image-build image-push teardown stage-data vpn sync-gitops-values

TF_DIR := terraform

## Terraform
tf-init:
	cd $(TF_DIR) && terraform init

tf-validate:
	cd $(TF_DIR) && terraform fmt -recursive -check && terraform validate

tf-plan:
	cd $(TF_DIR) && terraform plan

## Strict manifest validation (helm render + gitops) against cue/schema.cue
validate-manifests:
	./scripts/validate-manifests.sh

## Docker (buildx; amd64 even on arm64 hosts)
image-build:
	./scripts/build-image.sh

image-push:
	PUSH=1 ./scripts/build-image.sh

## Stage Kinetics-400 from the persistent archive bucket into the data bucket
## (ARCHIVE_BUCKET=<bucket> make stage-data)
stage-data:
	./scripts/stage-data.sh sync

vpn:
	./scripts/vpn-connect.sh

sync-gitops-values:
	./scripts/sync-gitops-values.sh

teardown:
	./scripts/teardown.sh

validate: tf-validate validate-manifests

lint: validate
