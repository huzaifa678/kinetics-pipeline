data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # /19 private subnets give plenty of IPs for GPU nodes + pods.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway = true
  # Single NAT gateway: cheaper. For prod HA, set to false (one per AZ).
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS + Karpenter subnet discovery.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = var.tags
}
