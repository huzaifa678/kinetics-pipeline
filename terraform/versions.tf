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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      # Latest major. (No v4 exists — 3.x is newest; it uses attribute-style
      # `kubernetes = {}` config instead of the old nested block.)
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    # Applies the ci-deployer RBAC manifest (terraform/rbac/ci-deployer.yaml).
    # gavinbunney/kubectl over hashicorp's kubernetes_manifest: it doesn't need a
    # server-side dry-run (and thus cluster read) at PLAN time, so it doesn't 401
    # on the read-only plan role for a resource that isn't in state yet.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
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

# These two providers talk to the EKS cluster created in this same config.
# They authenticate via the cluster endpoint + a short-lived token.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  # helm provider v3 uses attribute-style config (note the `=` signs).
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

# Same exec-auth as the kubernetes/helm providers. load_config_file=false so it
# never falls back to a kubeconfig on the runner.
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}
