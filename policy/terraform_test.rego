package main

import rego.v1

test_deny_ssh_world_v4 if {
	deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.bad",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv4": "0.0.0.0/0",
			"ip_protocol": "tcp",
			"from_port": 22,
			"to_port": 22,
		}},
	}]}
}

test_deny_ssh_inside_range if {
	deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.range",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv4": "0.0.0.0/0",
			"ip_protocol": "tcp",
			"from_port": 0,
			"to_port": 65535,
		}},
	}]}
}

test_deny_all_protocol_world if {
	deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.allproto",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv4": "0.0.0.0/0",
			"ip_protocol": "-1",
			"from_port": 0,
			"to_port": 0,
		}},
	}]}
}

test_deny_ssh_world_v6 if {
	deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.v6",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv6": "::/0",
			"ip_protocol": "tcp",
			"from_port": 3389,
			"to_port": 3389,
		}},
	}]}
}

test_allow_https_world if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.https",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv4": "0.0.0.0/0",
			"ip_protocol": "tcp",
			"from_port": 443,
			"to_port": 443,
		}},
	}]}
}

test_allow_ssh_private_cidr if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.bastion",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"cidr_ipv4": "10.0.0.0/8",
			"ip_protocol": "tcp",
			"from_port": 22,
			"to_port": 22,
		}},
	}]}
}

test_no_deny_on_destroy if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.gone",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["delete"], "after": null},
	}]}
}

test_deny_legacy_inline_ssh if {
	deny with input as {"resource_changes": [{
		"address": "aws_security_group.legacy",
		"type": "aws_security_group",
		"change": {"actions": ["create"], "after": {"ingress": [{
			"protocol": "tcp",
			"from_port": 20,
			"to_port": 25,
			"cidr_blocks": ["0.0.0.0/0"],
		}]}},
	}]}
}

test_warn_stateful_destroy if {
	warn with input as {"resource_changes": [{
		"address": "aws_s3_bucket.checkpoints",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"], "after": null},
	}]}
}

test_warn_iam_wildcard_admin if {
	warn with input as {"resource_changes": [{
		"address": "aws_iam_policy.too_broad",
		"type": "aws_iam_policy",
		"change": {"actions": ["create"], "after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"}},
	}]}
}

test_no_warn_iam_wildcard_karpenter_exempt if {
	count(warn) == 0 with input as {"resource_changes": [{
		"address": "module.eks.aws_iam_policy.karpenter_controller",
		"type": "aws_iam_policy",
		"change": {"actions": ["create"], "after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"}},
	}]}
}
