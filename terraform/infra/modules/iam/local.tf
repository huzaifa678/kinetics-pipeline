locals {
  account_id               = data.aws_caller_identity.current.account_id
  region                   = data.aws_region.current.name
  partition                = data.aws_partition.current.partition
  karpenter_node_role_name = "${var.name}-karpenter-node"
}