# ===========================================================================
# CLUSTER layer — everything that talks to the K8s API (kubernetes/helm/kubectl
# providers), plus the Pod Identity associations that glue in-cluster SAs to IAM
# roles. Providers are configured from the infra layer's remote state, so this is
# a clean, un-targeted `terraform apply` and destroys independently of the cluster.
# Apply order: infra first, then this. On the VPC runner / on the Client VPN.
# ===========================================================================

# CI-deployer RBAC (rbac/ci-deployer.yaml) applied via the kubectl provider.
# Gated on manage_argocd + at least one deployer principal (read from infra).
# Bootstrap caveat: the FIRST apply creating this must run as a cluster admin
# (the runner/deployer can't self-grant — k8s escalation-prevention).
module "ci_deployer_rbac" {
  source = "./modules/ci_deployer_rbac"
  count  = var.manage_argocd && length(local.infra.cluster_deployer_principal_arns) > 0 ? 1 : 0

  manifest_path = abspath("${path.module}/rbac/ci-deployer.yaml")
}

# In-cluster add-ons: ArgoCD bootstrap (manage_argocd) + Pod Identity associations
# + the app-layer helm/EKS add-ons (manage_incluster_addons). Wired from infra
# remote-state outputs.
module "addons" {
  source = "./modules/addons"

  cluster_name = local.infra.eks_cluster_name
  environment  = local.infra.environment

  ack_sagemaker_role_arn = local.infra.ack_sagemaker_role_arn
  karpenter_role_arn     = local.infra.karpenter_role_arn
  etl_shards_role_arn    = local.infra.etl_shards_role_arn
  image_updater_role_arn = local.infra.image_updater_role_arn

  enable_argocd            = var.enable_argocd
  enable_hyperpod_operator = var.enable_hyperpod_operator
  hyperpod_cluster_arn     = local.infra.hyperpod_cluster_arn
  gitops_repo_url          = var.gitops_repo_url
  gitops_repo_revision     = var.gitops_repo_revision

  region                     = local.infra.region
  vpc_id                     = local.infra.vpc_id
  enable_aws_lb_controller   = local.infra.enable_aws_lb_controller
  enable_external_dns        = local.infra.enable_external_dns
  aws_lbc_role_arn           = local.infra.aws_lbc_role_arn
  external_dns_role_arn      = local.infra.external_dns_role_arn
  external_dns_domain_filter = local.infra.external_dns_domain_filter
  amp_remote_write_role_arn  = local.infra.amp_remote_write_role_arn
  otel_xray_role_arn         = local.infra.otel_xray_role_arn
  enable_managed_prometheus  = local.infra.enable_managed_prometheus
  enable_xray_tracing        = local.infra.enable_xray_tracing
  manage_incluster_addons    = var.manage_incluster_addons
  manage_argocd              = var.manage_argocd

  aws_lb_controller_chart_version = var.aws_lb_controller_chart_version
  external_dns_chart_version      = var.external_dns_chart_version

  tags = local.common_tags

  # RBAC must exist before argocd install so the deployer role is authorized.
  depends_on = [module.ci_deployer_rbac]
}

# Advisory check (HyperPod gotcha #1): warns if the ArgoCD-managed
# hyperpod-dependencies chart isn't Synced+Healthy. Non-blocking.
module "hyperpod_deps_check" {
  source = "./modules/hyperpod_deps_check"
  count  = var.manage_argocd ? 1 : 0

  depends_on = [module.addons]
}
