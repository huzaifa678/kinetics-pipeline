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
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_type = var.system_node_instance_type
  system_node_desired_size  = var.system_node_desired_size

  cluster_admin_principal_arns = var.cluster_admin_principal_arns
  enable_hyperpod_operator     = var.enable_hyperpod_operator

  # Lock the public EKS API endpoint to the VPC NAT gateway's Elastic IP — the
  # egress IP for AWS Client VPN clients routed through this VPC — plus any extra
  # CIDRs (e.g. CI egress) from var.cluster_endpoint_public_access_cidrs.
  cluster_endpoint_public_access_cidrs = concat(
    [for ip in module.vpc.nat_public_ips : "${ip}/32"],
    var.cluster_endpoint_public_access_cidrs,
  )

  # Allow on-VPN clients to reach the private API endpoint on 443.
  vpn_client_cidr_block = var.enable_client_vpn ? var.vpn_client_cidr_block : ""

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# AWS Client VPN — SAML federated auth via IAM Identity Center. Associated to
# the private subnets so client egress is the NAT EIP and the EKS private
# endpoint is reachable. Disabled until enable_client_vpn + SAML metadata set.
# ---------------------------------------------------------------------------
module "client_vpn" {
  source = "./modules/client_vpn"
  count  = var.enable_client_vpn ? 1 : 0

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = var.vpc_cidr
  subnet_ids        = module.vpc.private_subnet_ids
  client_cidr_block = var.vpn_client_cidr_block

  saml_metadata_document              = file("${path.module}/${var.vpn_saml_metadata_file}")
  self_service_saml_metadata_document = var.vpn_self_service_saml_metadata_file == "" ? "" : file("${path.module}/${var.vpn_self_service_saml_metadata_file}")

  split_tunnel       = var.vpn_split_tunnel
  authorize_internet = var.vpn_authorize_internet

  # Assign Identity Center users/groups to the SAML app (so VPN auth works).
  saml_application_arn                = var.vpn_saml_application_arn
  saml_assignment_user_names          = var.vpn_saml_assignment_user_names
  saml_assignment_group_display_names = var.vpn_saml_assignment_group_display_names

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

  enable_gpu_autoscaling = var.enable_gpu_autoscaling
  autoscaler_role_arn    = module.iam.hyperpod_autoscaler_role_arn

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Experiment tracking: SageMaker-managed MLflow tracking server + artifact
# bucket. The trainer logs params/metrics/artifacts here (--mlflow-tracking-uri
# = the server ARN). Grants the HyperPod exec role MLflow log access.
# COST: the server bills hourly while running — toggle enable_mlflow off (or
# terraform destroy -target module.mlflow) between experiment campaigns.
# ---------------------------------------------------------------------------
module "mlflow" {
  source = "./modules/mlflow"
  count  = var.enable_mlflow ? 1 : 0

  name                         = local.name
  trainer_role_name            = module.iam.hyperpod_execution_role_name
  tracking_server_size         = var.mlflow_tracking_server_size
  mlflow_version               = var.mlflow_version
  automatic_model_registration = var.mlflow_automatic_model_registration

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Cost guardrails: AWS Budgets, anomaly detection, auto-stop Lambda.
# ---------------------------------------------------------------------------
module "cost" {
  source = "./modules/cost"

  name               = local.name
  project_tag        = var.project
  region             = var.region
  monthly_budget_usd = var.monthly_budget_usd
  alert_emails       = var.budget_alert_emails
  # When Karpenter autoscaling is on, Karpenter owns GPU scale-to-zero (via
  # consolidation). The auto-stop Lambda would call UpdateCluster and fight
  # Karpenter — possibly killing a live run — so disable it in that mode.
  auto_stop_idle_minutes = var.enable_gpu_autoscaling ? 0 : var.auto_stop_idle_minutes
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

# ---------------------------------------------------------------------------
# Container registry for the training image. CI builds with buildx (linux/amd64)
# and pushes here; the GitOps repo's image tag is then bumped to the new SHA.
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  repository_name = var.ecr_repository_name
  tags            = local.common_tags
}

# ---------------------------------------------------------------------------
# CI/CD identity: GitHub Actions OIDC provider + least-privilege roles (ECR
# push, Terraform plan, Terraform apply). Keyless — no static AWS access keys.
# ---------------------------------------------------------------------------
module "cicd" {
  source = "./modules/cicd"
  count  = var.enable_github_oidc ? 1 : 0

  name                 = local.name
  github_owner         = var.github_owner
  github_repo          = var.github_repo
  create_oidc_provider = var.create_github_oidc_provider
  oidc_provider_arn    = var.github_oidc_provider_arn
  ecr_repository_arn   = module.ecr.repository_arn
  state_bucket         = var.terraform_state_bucket

  tags = local.common_tags
}
