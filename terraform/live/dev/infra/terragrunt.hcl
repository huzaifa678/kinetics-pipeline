# dev / INFRA layer (AWS-API only). Values from Terragrunt inputs (was
# terraform.tfvars.dev). enable_hyperpod defaults to true; the cold-start two-phase
# forces it via a CLI -var override. Dev leaves many prod-only toggles at their
# variable defaults (no CI deployer/bootstrap/viewer principals, no frontend/cognito/
# waf, no MSK, no mlflow) — matching the old dev tfvars exactly.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/infra"
}

dependency "network" {
  config_path  = "../network"
  skip_outputs = true
}

inputs = merge(local.env.inputs, {
  kubernetes_version        = "1.34"
  system_node_instance_type = "m6i.large"
  system_node_desired_size  = 2

  cluster_admin_principal_arns = [
    "arn:aws:iam::533267178572:user/terraform",
  ]
  cluster_endpoint_public_access_cidrs = []

  enable_client_vpn              = true
  vpn_saml_metadata_file         = "client-vpn-saml-metadata.xml"
  vpn_client_cidr_block          = "10.100.0.0/22"
  vpn_split_tunnel               = true
  vpn_authorize_internet         = false
  vpn_saml_application_arn       = "arn:aws:sso::533267178572:application/ssoins-7223d8444c116ea9/apl-7223f4c6c415e416"
  vpn_saml_assignment_user_names = ["HuzaifaGill"]

  enable_msk = false

  gpu_instance_type              = "ml.g5.12xlarge"
  gpu_instance_count             = 0
  enable_hyperpod_operator       = true
  hyperpod_system_instance_count = 1

  monthly_budget_usd     = 100
  budget_alert_emails    = ["huzaifaahmad2210@gmail.com"]
  auto_stop_idle_minutes = 30

  fsx_storage_capacity_gb   = 1200
  checkpoint_retention_days = 30

  enable_argocd        = true
  gitops_repo_url      = "https://github.com/huzaifa678/Kinetics-Continious-Delivery.git"
  gitops_repo_revision = "main"

  enable_aws_lb_controller  = true
  enable_external_dns       = true
  inference_domain_name     = ""
  inference_route53_zone_id = ""

  enable_managed_prometheus = true
  enable_xray_tracing       = true
  enable_managed_grafana    = false
})
