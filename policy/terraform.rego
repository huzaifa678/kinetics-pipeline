package main

import rego.v1

sensitive_ports := {22, 3389} # SSH, RDP

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_vpc_security_group_ingress_rule"
	after := rc.change.after
	after.cidr_ipv4 == "0.0.0.0/0"
	sensitive_ports[after.from_port]
	msg := sprintf("%s: security-group ingress opens port %d to 0.0.0.0/0", [rc.address, after.from_port])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_security_group"
	ingress := rc.change.after.ingress[_]
	ingress.cidr_blocks[_] == "0.0.0.0/0"
	sensitive_ports[ingress.from_port]
	msg := sprintf("%s: security-group ingress opens port %d to 0.0.0.0/0", [rc.address, ingress.from_port])
}

warn contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_eks_cluster"
	cfg := rc.change.after.vpc_config[_]
	cfg.public_access_cidrs[_] == "0.0.0.0/0"
	msg := sprintf("%s: EKS public endpoint is open to 0.0.0.0/0", [rc.address])
}

warn contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_s3_bucket"
	not bucket_has_sse(rc.address)
	msg := sprintf("%s: S3 bucket has no server-side-encryption config in this plan", [rc.address])
}

bucket_has_sse(bucket_addr) if {
	rc := input.resource_changes[_]
	rc.type == "aws_s3_bucket_server_side_encryption_configuration"
	# heuristic: an SSE config resource exists for the same base name
	contains(rc.address, trim_suffix(bucket_addr, ".this"))
}
