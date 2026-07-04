terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60.0"
    }
    # HyperPod (SageMaker::Cluster) is only exposed via the Cloud Control
    # provider — the classic aws provider has no aws_sagemaker_cluster resource.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
    # Self-signed server certificate for the Client VPN endpoint (clients
    # authenticate via SAML/IAM Identity Center, not mutual certs).
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    # SASL/SCRAM password generation for the prod MSK posture.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }

  # INFRA layer (AWS-API only). The kubernetes/helm/kubectl providers and the
  # in-cluster resources live in the CLUSTER layer (terraform/cluster), which
  # reads this layer's outputs via terraform_remote_state. Keeping them out of
  # here is the whole point of the split: a provider must not be configured from
  # a resource managed in the same state (breaks create ordering + destroy).
  backend "s3" {
    bucket       = "kinetics-pipeline-bucket-ec371a2a"
    key          = "kinetics-pipeline-bucket/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "awscc" {
  region = var.region
}
