package terragrunt

import rego.v1

good_unit := {
	"remote_state": {
		"backend": "s3",
		"config": {
			"backend": "s3",
			"bucket": "kinetics-pipeline-bucket-ec371a2a",
			"encrypt": true,
			"key": "kinetics-pipeline-bucket/network.tfstate",
			"region": "us-east-1",
			"use_lockfile": true,
		},
	},
	"inputs": {
		"project": "kinetics-pipeline",
		"region": "us-east-1",
		"environment": "prod",
	},
	"terraform": {"source": "/repo/terraform/network"},
}

test_allow_good_unit if {
	count(deny) == 0 with input as good_unit
	count(warn) == 0 with input as good_unit
}

test_deny_non_s3_backend if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/backend", "value": "local"}])
}

test_deny_unencrypted_state if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/config/encrypt", "value": false}])
}

test_deny_missing_encrypt if {
	deny with input as json.patch(good_unit, [{"op": "remove", "path": "/remote_state/config/encrypt"}])
}

test_deny_no_lockfile if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/config/use_lockfile", "value": false}])
}

test_deny_unapproved_bucket if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/config/bucket", "value": "some-other-bucket"}])
}

test_deny_empty_state_key if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/config/key", "value": ""}])
}

test_deny_missing_required_input if {
	deny with input as json.patch(good_unit, [{"op": "remove", "path": "/inputs/region"}])
}

test_deny_wrong_project if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/inputs/project", "value": "not-kinetics"}])
}

test_deny_remote_source if {
	deny with input as json.patch(good_unit, [{"op": "replace", "path": "/terraform/source", "value": "git::https://example.com/mod.git//x"}])
}

test_warn_source_key_mismatch if {
	warn with input as json.patch(good_unit, [{"op": "replace", "path": "/remote_state/config/key", "value": "kinetics-pipeline-bucket/cluster.tfstate"}])
}
