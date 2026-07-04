terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60.0"
    }
  }

  # RUNNER layer — the self-hosted GitHub Actions runner is a chicken-egg CI
  # prerequisite (like terraform/bootstrap): CI can't create the runner CI runs
  # on. Its own state so it stands up with a clean, un-targeted apply from a
  # laptop, reading the VPC from the infra layer's remote state.
  backend "s3" {
    bucket       = "kinetics-pipeline-bucket-ec371a2a"
    key          = "kinetics-pipeline-bucket/runner.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = local.infra.environment
      ManagedBy   = "terraform"
    }
  }
}
