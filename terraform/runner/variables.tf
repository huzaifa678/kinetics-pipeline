variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name (tags only; the infra layer owns naming)."
  type        = string
  default     = "kinetics-pipeline"
}

variable "enable_self_hosted_runner" {
  description = "Create the VPC self-hosted GitHub Actions runner. Applying this layer generally means you want it."
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub org/user that owns the infra repo."
  type        = string
  default     = "huzaifa678"
}

variable "github_repo" {
  description = "GitHub repo name holding this Terraform / the CI workflows."
  type        = string
  default     = "kinetics-pipeline"
}
