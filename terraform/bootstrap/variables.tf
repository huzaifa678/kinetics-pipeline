variable "project" {
  type    = string
  default = "kinetics"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "github_owner" {
  type    = string
  default = "huzaifa678"
}

variable "github_repo" {
  type    = string
  default = "kinetics-pipeline"
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding the MAIN stack's Terraform state. Scopes the CI tf-plan/tf-apply role S3 permissions to it. Required (no default)."
  type        = string
}

variable "ecr_repository_name" {
  type    = string
  default = "kinetics-training"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "region" {
  type    = string
  default = "us-east-1"
}