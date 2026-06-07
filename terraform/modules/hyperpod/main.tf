terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    awscc = {
      source = "hashicorp/awscc"
    }
  }
}

locals {
  gpu_group_name = "gpu-training"
}

resource "aws_s3_object" "lifecycle_script" {
  bucket  = var.lifecycle_bucket
  key     = "lifecycle/on_create.sh"
  content = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    echo "HyperPod node bootstrap for ${var.name}"
    # Place NCCL/EFA env, FSx mounts, DCGM exporter install, etc. here.
  EOT
}


resource "awscc_sagemaker_cluster" "this" {
  cluster_name = var.name

  orchestrator = {
    eks = {
      cluster_arn = var.eks_cluster_arn
    }
  }

  instance_groups = [{
    instance_group_name = local.gpu_group_name
    instance_type       = var.gpu_instance_type
    instance_count      = var.gpu_instance_count
    execution_role      = var.execution_role_arn
    threads_per_core    = var.gpu_threads_per_core

    life_cycle_config = {
      on_create     = "on_create.sh"
      source_s3_uri = "s3://${var.lifecycle_bucket}/lifecycle/"
    }
  }]

  vpc_config = {
    security_group_ids = var.security_group_ids
    subnets            = var.subnet_ids
  }

  tags = [for k, v in var.tags : { key = k, value = v }]

  lifecycle {
    ignore_changes = [instance_groups]
  }

  depends_on = [aws_s3_object.lifecycle_script]
}
