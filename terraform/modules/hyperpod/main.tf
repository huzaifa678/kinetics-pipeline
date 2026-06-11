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

  # GPU instance-group names.
  #   * Autoscaling: one group PER private subnet (AZ). HyperPod's Karpenter
  #     requires each instance group's subnets to be single-AZ, and the groups
  #     must start at 0 nodes (Karpenter scales them up on pending GPU pods and
  #     consolidates back to 0). The HyperpodNodeClass in the GitOps repo
  #     references these names — keep them in sync (terraform output
  #     hyperpod_gpu_instance_group_names).
  #   * Fixed (autoscaling off): the original single manually-scaled group.
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

  instance_groups = var.enable_gpu_autoscaling ? local.autoscaling_groups : local.fixed_groups
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

  # Karpenter-based autoscaling (managed by the HyperPod control plane — no
  # controller to install in-cluster). "Continuous" provisioning lets Karpenter
  # add/remove nodes from the count-0 instance groups on demand. cluster_role is
  # the role HyperPod assumes to call BatchAdd/DeleteClusterNodes.
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
    # Karpenter mutates the live node counts; never let Terraform revert them.
    ignore_changes = [instance_groups]
  }

  depends_on = [aws_s3_object.lifecycle_script]
}
