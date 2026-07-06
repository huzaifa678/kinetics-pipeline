# Self-hosted GitHub Actions runner in the VPC. Egress = the NAT EIP already
# allow-listed on the EKS public endpoint, so terraform-plan/apply run here can
# reach the VPN-locked cluster API. Clean, un-targeted apply — the VPC comes from
# the network layer's remote state (no -target slicing, and no dependency on the
# full infra layer). Seed the PAT + cycle the ASG with scripts/bootstrap-runner.sh
# after this applies.
module "github_runner" {
  source = "./modules/github_runner"
  count  = var.enable_self_hosted_runner ? 1 : 0

  name         = local.network.name
  vpc_id       = local.network.vpc_id
  subnet_ids   = local.network.private_subnet_ids
  github_owner = var.github_owner
  github_repo  = var.github_repo

  tags = {
    Project     = var.project
    Environment = local.network.environment
    ManagedBy   = "terraform"
  }
}
