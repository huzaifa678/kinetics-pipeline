locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name     = local.name
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------
# EKS control plane + always-on CPU system node group.
# GPUs do NOT live here — they live in the HyperPod cluster below.
# ---------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  name               = local.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_type = var.system_node_instance_type
  system_node_desired_size  = var.system_node_desired_size

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM: HyperPod execution role + IRSA roles for in-cluster controllers.
# ---------------------------------------------------------------------------
# Karpenter SQS interruption queue + EventBridge rules (Spot-safe draining).
module "karpenter" {
  source = "./modules/karpenter"

  name = local.name
  tags = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name                             = local.name
  cluster_name                     = module.eks.cluster_name
  data_bucket_arn                  = module.storage.data_bucket_arn
  checkpoint_bucket_arn            = module.storage.checkpoint_bucket_arn
  karpenter_interruption_queue_arn = module.karpenter.interruption_queue_arn

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Storage: S3 (data + checkpoints, with lifecycle) and FSx for Lustre.
# ---------------------------------------------------------------------------
module "storage" {
  source = "./modules/storage"

  name                      = local.name
  private_subnet_id         = module.vpc.private_subnet_ids[0]
  vpc_id                    = module.vpc.vpc_id
  fsx_storage_capacity_gb   = var.fsx_storage_capacity_gb
  checkpoint_retention_days = var.checkpoint_retention_days

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# HyperPod GPU cluster, orchestrated by the EKS control plane.
# Defaults to scale-to-zero (gpu_instance_count = 0).
# ---------------------------------------------------------------------------
module "hyperpod" {
  source = "./modules/hyperpod"

  name                 = local.name
  eks_cluster_arn      = module.eks.cluster_arn
  execution_role_arn   = module.iam.hyperpod_execution_role_arn
  subnet_ids           = module.vpc.private_subnet_ids
  security_group_ids   = [module.eks.node_security_group_id]
  lifecycle_bucket     = module.storage.lifecycle_bucket_name
  lifecycle_bucket_arn = module.storage.lifecycle_bucket_arn

  gpu_instance_type    = var.gpu_instance_type
  gpu_instance_count   = var.gpu_instance_count
  gpu_threads_per_core = var.gpu_threads_per_core

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Cost guardrails: AWS Budgets, anomaly detection, auto-stop Lambda.
# ---------------------------------------------------------------------------
module "cost" {
  source = "./modules/cost"

  name                   = local.name
  project_tag            = var.project
  region                 = var.region
  monthly_budget_usd     = var.monthly_budget_usd
  alert_emails           = var.budget_alert_emails
  auto_stop_idle_minutes = var.auto_stop_idle_minutes
  hyperpod_cluster_name  = module.hyperpod.cluster_name
  gpu_instance_group     = module.hyperpod.gpu_instance_group_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# In-cluster add-ons via Helm: Karpenter, ACK SageMaker controller,
# DCGM/Prometheus GPU monitoring, and (optionally) ArgoCD for GitOps.
# ---------------------------------------------------------------------------
module "addons" {
  source = "./modules/addons"

  name         = local.name
  region       = var.region
  cluster_name = module.eks.cluster_name

  ack_sagemaker_role_arn = module.iam.ack_sagemaker_role_arn
  karpenter_role_arn     = module.iam.karpenter_role_arn

  enable_argocd        = var.enable_argocd
  gitops_repo_url      = var.gitops_repo_url
  gitops_repo_revision = var.gitops_repo_revision

  tags = local.common_tags

  depends_on = [module.eks]
}
