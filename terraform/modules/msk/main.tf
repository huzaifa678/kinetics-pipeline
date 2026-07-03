locals {
  # number_of_broker_nodes must be a multiple of the client-subnet (AZ) count.
  broker_count = var.broker_count != null ? var.broker_count : length(var.private_subnet_ids)
  scram        = var.client_authentication == "sasl_scram"
  iam          = var.client_authentication == "iam"
}

resource "aws_security_group" "msk" {
  name        = "${var.name}-msk"
  description = "MSK brokers - intra-VPC Kafka access only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-msk" })
}

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

  # See header. unauthenticated for dev; SASL (scram or iam) for prod.
  client_authentication {
    unauthenticated = var.client_authentication == "unauthenticated"

    dynamic "sasl" {
      for_each = local.scram || local.iam ? [1] : []
      content {
        scram = local.scram
        iam   = local.iam
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = var.tags
}


resource "aws_kms_key" "scram" {
  count = local.scram ? 1 : 0

  description         = "${var.name} MSK SASL/SCRAM secret encryption"
  enable_key_rotation = true
  tags                = var.tags
}

resource "aws_kms_alias" "scram" {
  count = local.scram ? 1 : 0

  name          = "alias/${var.name}-msk-scram"
  target_key_id = aws_kms_key.scram[0].key_id
}

resource "random_password" "scram" {
  count = local.scram ? 1 : 0

  length  = 32
  special = false # keep it broker/CLI-safe
}

resource "aws_secretsmanager_secret" "scram" {
  count = local.scram ? 1 : 0

  name       = "AmazonMSK_${var.name}_scram"
  kms_key_id = aws_kms_key.scram[0].key_id
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "scram" {
  count = local.scram ? 1 : 0

  secret_id     = aws_secretsmanager_secret.scram[0].id
  secret_string = jsonencode({ username = var.scram_username, password = random_password.scram[0].result })
}

resource "aws_msk_scram_secret_association" "this" {
  count = local.scram ? 1 : 0

  cluster_arn     = aws_msk_cluster.this.arn
  secret_arn_list = [aws_secretsmanager_secret.scram[0].arn]

  depends_on = [aws_secretsmanager_secret_version.scram]
}
