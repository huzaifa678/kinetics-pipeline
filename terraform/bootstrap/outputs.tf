output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecr_repository_arn" {
  value = module.ecr.repository_arn
}

output "gha_ecr_push_role_arn" {
  value = module.cicd.ecr_push_role_arn
}

output "gha_terraform_plan_role_arn" {
  value = module.cicd.terraform_plan_role_arn
}

output "gha_terraform_apply_role_arn" {
  value = module.cicd.terraform_apply_role_arn
}

output "gha_cluster_bootstrap_role_arn" {
  value = module.cicd.cluster_bootstrap_role_arn
}

output "gha_gitops_contract_read_role_arn" {
  value = module.cicd.gitops_contract_read_role_arn
}

output "github_oidc_provider_arn" {
  value = module.cicd.oidc_provider_arn
}