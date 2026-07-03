locals {
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )

  name = "${var.project}-${var.environment}"
}

module "ecr" {
  source = "../modules/ecr"

  repository_name = var.ecr_repository_name
  tags            = local.common_tags
}

module "cicd" {
  source = "../modules/cicd"

  name = local.name

  github_owner = var.github_owner
  github_repo  = var.github_repo

  create_oidc_provider = true

  ecr_repository_arn = module.ecr.repository_arn

  state_bucket = var.terraform_state_bucket

  tags = local.common_tags
}