variable "name" {
  description = "Name prefix for the CI/CD roles."
  type        = string
}

variable "github_owner" {
  description = "GitHub org/user that owns the infra repo."
  type        = string
  default     = "huzaifa678"
}

variable "github_repo" {
  description = "GitHub repo name holding this Terraform (the CI workflows run here)."
  type        = string
  default     = "kinetics-pipeline"
}

variable "default_branch" {
  description = "Branch allowed to push images / run apply."
  type        = string
  default     = "main"
}

variable "apply_environment" {
  description = "GitHub Environment (with required reviewers) that may run terraform apply. Kept for back-compat; merged into apply_environments."
  type        = string
  default     = "production"
}

variable "apply_environments" {
  description = "GitHub Environments allowed to assume the apply role. The terraform-apply dispatch maps each tfvars profile to a same-named Environment, so configure required-reviewer protection per env (e.g. on `prod`) in repo Settings."
  type        = list(string)
  default     = ["production", "dev", "prod", "test", "novpn", "kafka"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (then set oidc_provider_arn)."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN (used when create_oidc_provider = false)."
  type        = string
  default     = ""
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repo the CI push role may write to."
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket holding the Terraform remote state (for the plan role)."
  type        = string
}

variable "apply_managed_policy" {
  description = "AWS managed policy attached to the apply role. AdministratorAccess by default (this stack provisions IAM/KMS/EKS)."
  type        = string
  default     = "AdministratorAccess"
}

variable "frontend_bucket_arn" {
  description = "SPA S3 bucket ARN — gates the frontend-deploy role (created only when non-empty)."
  type        = string
  default     = ""
}

variable "frontend_distribution_arn" {
  description = "CloudFront distribution ARN the deploy role may invalidate. Empty = all."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
