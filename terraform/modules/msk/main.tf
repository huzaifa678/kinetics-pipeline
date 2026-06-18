# ---------------------------------------------------------------------------
# Amazon MSK (provisioned) — Kafka backend for Seldon Core v2 Pipelines / async
# dataflow. Only needed when Seldon Pipelines are enabled; the sync Model + A/B
# Experiment path does NOT use Kafka, so the whole module is behind enable_msk
# (count) at the root and defaults off.
#
# Dev posture: TLS in transit, UNAUTHENTICATED client auth, locked to the VPC by
# the security group. No SASL/SCRAM => no Secrets-Manager-to-k8s credential
# bridge (no External Secrets Operator), so Seldon connects with plain SSL +
# the default CA bundle. Harden to SASL/SCRAM or IAM for prod.
# ---------------------------------------------------------------------------

locals {
  # number_of_broker_nodes must be a multiple of the client-subnet (AZ) count.
  broker_count = var.broker_count != null ? var.broker_count : length(var.private_subnet_ids)
}

resource "aws_security_group" "msk" {
  name        = "${var.name}-msk"
  description = "MSK brokers — intra-VPC Kafka access only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-msk" })
}

# Intra-VPC only (matches the storage/FSx SG style). Covers the broker ports
# (9092 plaintext, 9094 TLS, 9098 IAM) + inter-broker traffic.
resource "aws_vpc_security_group_ingress_rule" "msk_vpc" {
  security_group_id = aws_security_group.msk.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Intra-VPC Kafka (9092/9094/9098 + inter-broker)"
}

resource "aws_vpc_security_group_egress_rule" "msk_all" {
  security_group_id = aws_security_group.msk.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = local.broker_count

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.private_subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
  }

  # TLS in transit, no client auth — see header. Seldon connects over SSL.
  client_authentication {
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = var.tags
}
