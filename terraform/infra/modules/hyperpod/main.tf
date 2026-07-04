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
  life_cycle_config = {
    on_create     = "on_create.sh"
    source_s3_uri = "s3://${var.lifecycle_bucket}/lifecycle/"
  }

  gpu_group_names = var.enable_gpu_autoscaling ? [
    for i in range(length(var.subnet_ids)) : "gpu-training-az${i + 1}"
  ] : ["gpu-training"]

  # One count-0 GPU group per AZ, each pinned to a single-AZ subnet.
  autoscaling_groups = [for i, s in var.subnet_ids : {
    instance_group_name = "gpu-training-az${i + 1}"
    instance_type       = var.gpu_instance_type
    instance_count      = 0 # Karpenter owns the live count from here on.
    execution_role      = var.execution_role_arn
    threads_per_core    = var.gpu_threads_per_core
    life_cycle_config   = local.life_cycle_config
    # Single-AZ subnet per group (required by HyperPod Karpenter autoscaling).
    override_vpc_config = {
      security_group_ids = var.security_group_ids
      subnets            = [s]
    }
  }]

  # Original single fixed-count group (autoscaling disabled). override_vpc_config
  # is null so both branches share one object type for the conditional below.
  fixed_groups = [{
    instance_group_name = "gpu-training"
    instance_type       = var.gpu_instance_type
    instance_count      = var.gpu_instance_count
    execution_role      = var.execution_role_arn
    threads_per_core    = var.gpu_threads_per_core
    life_cycle_config   = local.life_cycle_config
    override_vpc_config = null
  }]


  system_group = [for _ in range(var.system_instance_count > 0 ? 1 : 0) : {
    instance_group_name = "system"
    instance_type       = var.system_instance_type
    instance_count      = var.system_instance_count
    execution_role      = var.execution_role_arn
    threads_per_core    = 1
    life_cycle_config   = local.life_cycle_config
    override_vpc_config = var.enable_gpu_autoscaling ? {
      security_group_ids = var.security_group_ids
      subnets            = [var.subnet_ids[0]]
    } : null
  }]

  instance_groups = concat(
    var.enable_gpu_autoscaling ? local.autoscaling_groups : local.fixed_groups,
    local.system_group,
  )
}

resource "aws_s3_object" "lifecycle_script" {
  bucket  = var.lifecycle_bucket
  key     = "lifecycle/on_create.sh"
  content = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    echo "HyperPod node bootstrap for ${var.name}"
  EOT
}


resource "awscc_sagemaker_cluster" "this" {
  cluster_name = var.name

  orchestrator = {
    eks = {
      cluster_arn = var.eks_cluster_arn
    }
  }

  auto_scaling = var.enable_gpu_autoscaling ? {
    mode             = "Enable"
    auto_scaler_type = "Karpenter"
  } : null
  node_provisioning_mode = var.enable_gpu_autoscaling ? "Continuous" : null
  cluster_role           = var.enable_gpu_autoscaling ? var.autoscaler_role_arn : null

  instance_groups = local.instance_groups

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
