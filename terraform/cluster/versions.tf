terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }

  backend "s3" {
    bucket       = "kinetics-pipeline-bucket-ec371a2a"
    key          = "kinetics-pipeline-bucket/cluster.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# All provider auth comes from the INFRA layer's remote-state outputs (stable
# values, never "unknown"), NOT from a resource in this state — that's the whole
# point of the layer split.
provider "aws" {
  region = local.infra.region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = local.infra.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.infra.eks_cluster_name, "--region", local.infra.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.infra.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.eks_cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.infra.eks_cluster_name, "--region", local.infra.region]
    }
  }
}

provider "kubectl" {
  host                   = local.infra.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.infra.eks_cluster_name, "--region", local.infra.region]
  }
}
