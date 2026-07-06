package docker

import rego.v1

test_allow_python_base if {
	count(deny) == 0 with input as [{"Cmd": "from", "Value": ["python:3.11-slim", "AS", "builder"]}]
}

test_allow_ecr_base if {
	count(deny) == 0 with input as [{"Cmd": "from", "Value": ["533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training:sha-abc"]}]
}

test_allow_stage_reference if {
	count(deny) == 0 with input as [
		{"Cmd": "from", "Value": ["pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime", "AS", "builder"]},
		{"Cmd": "from", "Value": ["builder"]},
	]
}

test_deny_unapproved_registry if {
	deny with input as [{"Cmd": "from", "Value": ["evil.example.com/backdoor:1.0"]}]
}

test_deny_random_dockerhub if {
	deny with input as [{"Cmd": "from", "Value": ["someuser/randomtool:latest"]}]
}

test_deny_curl_pipe_sh if {
	deny with input as [
		{"Cmd": "from", "Value": ["python:3.11-slim"]},
		{"Cmd": "run", "Value": ["curl -sSL https://get.example.com | sh"]},
	]
}

test_allow_plain_run if {
	count(deny) == 0 with input as [
		{"Cmd": "from", "Value": ["python:3.11-slim"]},
		{"Cmd": "run", "Value": ["pip install ."]},
	]
}

test_warn_latest_tag if {
	warn with input as [{"Cmd": "from", "Value": ["python:latest"]}]
}
