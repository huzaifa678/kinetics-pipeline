locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # SPA URL (custom domain or the default CloudFront URL) → Cognito callback/logout.
  spa_url = var.enable_frontend ? one(module.frontend[*].spa_url) : ""
  cognito_callback_urls = distinct(concat(
    local.spa_url != "" ? ["${local.spa_url}/"] : [],
    var.cognito_extra_callback_urls,
  ))
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

# ---------------------------------------------------------------------------
# MSK (Kafka) — backend for Seldon Core v2 Pipelines / async dataflow. Off by
# default (enable_msk); the sync Model + A/B Experiment path needs no Kafka.
# TLS in transit, unauthenticated, SG-locked to the VPC (see modules/msk).
# ---------------------------------------------------------------------------
module "msk" {
  source = "./modules/msk"
  count  = var.enable_msk ? 1 : 0

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  kafka_version          = var.kafka_version
  broker_instance_type   = var.msk_broker_instance_type
  broker_ebs_volume_size = var.msk_broker_ebs_volume_size
  client_authentication  = var.msk_client_authentication

  tags = local.common_tags
}

# ECR lives in the bootstrap stack now (terraform/bootstrap); look it up by name
# so the training/iam role can still be scoped to it. Bootstrap must be applied
# first (it is — it's the manual one-shot that also creates the CI roles).
data "aws_ecr_repository" "training" {
  name = var.ecr_repository_name
}

module "iam" {
  source = "./modules/iam"

  name                             = local.name
  cluster_name                     = module.eks.cluster_name
  data_bucket_arn                  = module.storage.data_bucket_arn
  checkpoint_bucket_arn            = module.storage.checkpoint_bucket_arn
  karpenter_interruption_queue_arn = module.karpenter.interruption_queue_arn
  ecr_repository_arn               = data.aws_ecr_repository.training.arn

  # Inference ingress + AWS-managed observability Pod Identity roles (gated).
  amp_workspace_arn        = module.observability.amp_workspace_arn
  enable_xray_tracing      = var.enable_xray_tracing
  enable_aws_lb_controller = var.enable_aws_lb_controller
  enable_external_dns      = var.enable_external_dns
  route53_zone_id          = var.inference_route53_zone_id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# AWS-managed observability (opt-in per env): AMP workspace (in-cluster
# Prometheus remote_writes to it) + AMG workspace (replaces in-cluster Grafana).
# Both internally count-gated; this module is inert when the flags are off.
# ---------------------------------------------------------------------------
module "observability" {
  source = "./modules/observability"

  name                      = local.name
  enable_managed_prometheus = var.enable_managed_prometheus
  enable_managed_grafana    = var.enable_managed_grafana

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Public inference frontend: Cognito (auth) + React SPA on S3/CloudFront, plus
# an optional regional WAF for the public inference ALB. Prod-only (gated).
# ---------------------------------------------------------------------------
module "cognito" {
  source = "./modules/cognito"
  count  = var.enable_cognito ? 1 : 0

  name                    = local.name
  hosted_ui_domain_prefix = var.cognito_hosted_ui_prefix
  callback_urls           = local.cognito_callback_urls
  logout_urls             = local.cognito_callback_urls

  tags = local.common_tags
}

module "frontend" {
  source = "./modules/frontend"
  count  = var.enable_frontend ? 1 : 0

  name            = local.name
  domain_name     = var.frontend_domain_name
  route53_zone_id = var.frontend_route53_zone_id
  enable_waf      = var.enable_waf

  tags = local.common_tags
}

# Regional WAFv2 for the public inference ALB (attached via the Ingress
# `wafv2-acl-arn` annotation by sync-gitops-values for prod).
resource "aws_wafv2_web_acl" "inference_api" {
  count = var.enable_waf && var.api_domain_name != "" ? 1 : 0

  name        = "${local.name}-api-waf"
  scope       = "REGIONAL"
  description = "${local.name} public inference ALB — managed common rules + rate limit"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-ratelimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-api-waf"
    sampled_requests_enabled   = true
  }

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
  vpc_cidr                  = var.vpc_cidr
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

  gpu_instance_type     = var.gpu_instance_type
  gpu_instance_count    = var.gpu_instance_count
  gpu_threads_per_core  = var.gpu_threads_per_core
  system_instance_count = var.hyperpod_system_instance_count

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
  cluster_name = module.eks.cluster_name
  environment  = var.environment

  ack_sagemaker_role_arn = module.iam.ack_sagemaker_role_arn
  karpenter_role_arn     = module.iam.karpenter_role_arn
  etl_shards_role_arn    = module.iam.etl_shards_role_arn
  image_updater_role_arn = module.iam.image_updater_role_arn

  enable_argocd            = var.enable_argocd
  enable_hyperpod_operator = var.enable_hyperpod_operator
  # Operator add-on's controller can only run on a HyperPod node, so it must wait
  # for the HyperPod cluster (its system group) — passing the ARN creates that
  # edge without blocking ArgoCD/cert-manager.
  hyperpod_cluster_arn = module.hyperpod.cluster_arn
  gitops_repo_url      = var.gitops_repo_url
  gitops_repo_revision = var.gitops_repo_revision

  region                     = var.region
  vpc_id                     = module.vpc.vpc_id
  enable_aws_lb_controller   = var.enable_aws_lb_controller
  enable_external_dns        = var.enable_external_dns
  aws_lbc_role_arn           = module.iam.aws_lbc_role_arn
  external_dns_role_arn      = module.iam.external_dns_role_arn
  external_dns_domain_filter = var.inference_domain_name
  amp_remote_write_role_arn  = module.iam.amp_remote_write_role_arn
  otel_xray_role_arn         = module.iam.otel_xray_role_arn

  aws_lb_controller_chart_version = var.aws_lb_controller_chart_version
  external_dns_chart_version      = var.external_dns_chart_version

  tags = local.common_tags

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Inference HTTPS endpoint: a public ACM cert (DNS-validated against the
# provided Route53 zone) consumed by the internal ALB Ingress. The A-record to
# the ALB is created by external-dns (the ALB name isn't known at apply time).
# Gated on inference_domain_name — nothing is created when it's empty.
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "inference" {
  count = var.inference_domain_name != "" ? 1 : 0

  domain_name       = var.inference_domain_name
  validation_method = "DNS"
  tags              = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "inference_cert_validation" {
  for_each = var.inference_domain_name != "" ? {
    for dvo in aws_acm_certificate.inference[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = var.inference_route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "inference" {
  count = var.inference_domain_name != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.inference[0].arn
  validation_record_fqdns = [for r in aws_route53_record.inference_cert_validation : r.fqdn]
}
