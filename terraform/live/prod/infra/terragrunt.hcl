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
  system_node_desired_size  = 3 

  cluster_admin_principal_arns = [
    "arn:aws:iam::533267178572:user/terraform",
  ]

  cluster_deployer_principal_arns = [
    "arn:aws:iam::533267178572:role/kinetics-pipeline-prod-gha-tf-apply",
  ]

  cluster_bootstrap_principal_arns = [
    "arn:aws:iam::533267178572:role/kinetics-pipeline-prod-gha-cluster-bootstrap",
  ]

  cluster_viewer_principal_arns = [
    "arn:aws:iam::533267178572:role/kinetics-pipeline-prod-gha-tf-plan",
  ]
  cluster_endpoint_public_access_cidrs = []

  enable_client_vpn              = true
  vpn_saml_metadata_file         = "client-vpn-saml-metadata.xml"
  vpn_client_cidr_block          = "10.100.0.0/22"
  vpn_split_tunnel               = true
  vpn_authorize_internet         = false
  vpn_saml_application_arn       = "arn:aws:sso::533267178572:application/ssoins-7223d8444c116ea9/apl-7223f4c6c415e416"
  vpn_saml_assignment_user_names = ["HuzaifaGill"]

  enable_msk                 = true
  kafka_version              = "3.6.0"
  msk_broker_instance_type   = "kafka.m5.large"
  msk_broker_ebs_volume_size = 100
  msk_client_authentication  = "sasl_scram"

  gpu_instance_type      = "ml.g5.12xlarge"
  gpu_instance_count     = 0
  enable_gpu_autoscaling = true

  enable_hyperpod_operator       = true
  hyperpod_system_instance_count = 1

  enable_mlflow = true

  monthly_budget_usd     = 2000
  budget_alert_emails    = ["huzaifaahmad2210@gmail.com"]
  auto_stop_idle_minutes = 30

  fsx_storage_capacity_gb   = 1200
  checkpoint_retention_days = 30

  enable_self_hosted_runner = true
  manage_argocd             = true
  manage_incluster_addons   = false
  enable_argocd             = true
  gitops_repo_url           = "https://github.com/huzaifa678/Kinetics-Continious-Delivery.git"
  gitops_repo_revision      = "main"

  enable_aws_lb_controller  = true
  enable_external_dns       = true
  core_domain_name          = "freeeasycrypto.com" 
  inference_domain_name     = ""
  inference_route53_zone_id = "" 

  enable_managed_prometheus = true
  enable_managed_grafana    = true
  enable_xray_tracing       = true

  enable_cognito           = true
  enable_frontend          = true
  enable_waf               = true
  frontend_domain_name     = ""                       
  api_domain_name          = "api.freeeasycrypto.com" 
  frontend_route53_zone_id = ""
  cognito_hosted_ui_prefix = "kinetics-prod-auth" 

  github_oidc_provider_arn = "arn:aws:iam::533267178572:oidc-provider/token.actions.githubusercontent.com"
})
