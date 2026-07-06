package main

import rego.v1

sensitive_ports := {22, 3389}

iam_wildcard_exceptions := {
	"karpenter",
	"hyperpod",
}

stateful_types := {
	"aws_s3_bucket",
	"aws_msk_cluster",
	"aws_fsx_lustre_file_system",
	"aws_efs_file_system",
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_dynamodb_table",
}

is_created_or_updated(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

is_destroyed(rc) if {
	some action in rc.change.actions
	action == "delete"
}

world_open_v4(cidr) if cidr == "0.0.0.0/0"

world_open_v6(cidr) if cidr == "::/0"

covers_sensitive_port(protocol, from_port, to_port) if {
	protocol == "-1" # all protocols == all ports
}

covers_sensitive_port(_, from_port, to_port) if {
	some p in sensitive_ports
	from_port <= p
	p <= to_port
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_vpc_security_group_ingress_rule"
	is_created_or_updated(rc)
	after := rc.change.after
	world_open_v4(after.cidr_ipv4)
	covers_sensitive_port(after.ip_protocol, after.from_port, after.to_port)
	msg := sprintf("%s: SG ingress opens %v:%v-%v to 0.0.0.0/0 (covers SSH/RDP)", [rc.address, after.ip_protocol, after.from_port, after.to_port])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_vpc_security_group_ingress_rule"
	is_created_or_updated(rc)
	after := rc.change.after
	world_open_v6(after.cidr_ipv6)
	covers_sensitive_port(after.ip_protocol, after.from_port, after.to_port)
	msg := sprintf("%s: SG ingress opens %v:%v-%v to ::/0 (covers SSH/RDP)", [rc.address, after.ip_protocol, after.from_port, after.to_port])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_security_group"
	is_created_or_updated(rc)
	ingress := rc.change.after.ingress[_]
	world_open_v4(ingress.cidr_blocks[_])
	covers_sensitive_port(ingress.protocol, ingress.from_port, ingress.to_port)
	msg := sprintf("%s: SG ingress opens %v:%v-%v to 0.0.0.0/0 (covers SSH/RDP)", [rc.address, ingress.protocol, ingress.from_port, ingress.to_port])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_security_group"
	is_created_or_updated(rc)
	ingress := rc.change.after.ingress[_]
	world_open_v6(ingress.ipv6_cidr_blocks[_])
	covers_sensitive_port(ingress.protocol, ingress.from_port, ingress.to_port)
	msg := sprintf("%s: SG ingress opens %v:%v-%v to ::/0 (covers SSH/RDP)", [rc.address, ingress.protocol, ingress.from_port, ingress.to_port])
}

warn contains msg if {
	rc := input.resource_changes[_]
	rc.type == "aws_eks_cluster"
	is_created_or_updated(rc)
	cfg := rc.change.after.vpc_config[_]
	cfg.public_access_cidrs[_] == "0.0.0.0/0"
	msg := sprintf("%s: EKS public endpoint is open to 0.0.0.0/0", [rc.address])
}

warn contains msg if {
	rc := input.resource_changes[_]
	stateful_types[rc.type]
	is_destroyed(rc)
	msg := sprintf("%s: plan DESTROYS a stateful resource (%s) — confirm this is intended", [rc.address, rc.type])
}

warn contains msg if {
	rc := input.resource_changes[_]
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	is_created_or_updated(rc)
	not exempt_iam_wildcard(rc.address)
	stmt := json.unmarshal(rc.change.after.policy).Statement[_]
	stmt.Effect == "Allow"
	wildcard(stmt.Action)
	wildcard(stmt.Resource)
	msg := sprintf("%s: IAM policy allows Action:* on Resource:* (wildcard admin)", [rc.address])
}

wildcard(v) if v == "*"

wildcard(v) if {
	is_array(v)
	v[_] == "*"
}

exempt_iam_wildcard(addr) if {
	some frag in iam_wildcard_exceptions
	contains(addr, frag)
}
