package terragrunt

import rego.v1

# Guardrails on the RENDERED Terragrunt config (`terragrunt render --format json`),
# evaluated per live/<env>/<layer> unit. This complements policy/terraform.rego,
# which gates the tfplan JSON (per-resource plan changes). These rules instead gate
# the *unit wiring itself* — backend safety + required identity inputs + source
# hygiene — and are AWS-free, so terragrunt-test can run them on every PR across all
# four layers (network/infra/cluster/runner) and both envs (dev/prod).
# Approved state-bucket prefix (the main stack's bucket is kinetics-pipeline-bucket-*;
# bootstrap uses kinetics-bootstrap-bucket — both share the kinetics- prefix).
approved_bucket_prefix := "kinetics-"

required_inputs := {"project", "region", "environment"}


# Backend safety

deny contains msg if {
	input.remote_state.backend != "s3"
	msg := sprintf("remote_state backend must be s3, got %q", [input.remote_state.backend])
}

deny contains msg if {
	input.remote_state.config.encrypt != true
	msg := "remote_state.config.encrypt must be true (state holds secret ARNs / cluster CA)"
}

deny contains msg if {
	input.remote_state.config.use_lockfile != true
	msg := "remote_state.config.use_lockfile must be true (S3-native state locking)"
}

deny contains msg if {
	bucket := input.remote_state.config.bucket
	not startswith(bucket, approved_bucket_prefix)
	msg := sprintf("remote_state bucket %q is not an approved %s* bucket", [bucket, approved_bucket_prefix])
}

# The state key must be non-empty — an unresolved local.state_keys[layer] lookup
# (e.g. a mis-named live dir the layer map does not know) renders as "".
deny contains msg if {
	key := input.remote_state.config.key
	key == ""
	msg := "remote_state.config.key is empty (live dir basename is not in root.hcl's state_keys map)"
}


# Required identity inputs

deny contains msg if {
	some key in required_inputs
	not input.inputs[key]
	msg := sprintf("required input %q is missing from the unit", [key])
}

deny contains msg if {
	input.inputs.project != "kinetics-pipeline"
	msg := sprintf("input project must be kinetics-pipeline (CI role names key off it), got %q", [input.inputs.project])
}


# Source hygiene

# Every live unit must source an in-repo terraform/<layer> module — a stray remote
# or drifted source is an org red flag (registry pins live inside the modules).
deny contains msg if {
	src := input.terraform.source
	not contains(src, "/terraform/")
	msg := sprintf("terraform.source %q does not reference an in-repo terraform/<layer> module", [src])
}

# The rendered source should end in the layer dir that matches this unit's state key.
# Advisory (warn) because the env/layer are not otherwise available to the policy.
warn contains msg if {
	src := input.terraform.source
	endswith(src, "/network")
	not endswith(input.remote_state.config.key, "network.tfstate")
	msg := sprintf("network module sourced but state key is %q", [input.remote_state.config.key])
}
