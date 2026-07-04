# Self-hosted GitHub Actions runner in the VPC. Egress = the NAT EIP already
# allow-listed on the EKS public endpoint, so terraform-plan/apply run here can
# reach the VPN-locked cluster API. Clean, un-targeted apply — the VPC comes from
# the infra layer's remote state (no -target slicing). Seed the PAT + cycle the
# ASG with scripts/bootstrap-runner.sh after this applies.
module "github_runner" {
  source = "./modules/github_runner"
  count  = var.enable_self_hosted_runner ? 1 : 0

  name         = local.infra.name
  vpc_id       = local.infra.vpc_id
  subnet_ids   = local.infra.private_subnet_ids
  github_owner = var.github_owner
  github_repo  = var.github_repo

  tags = {
    Project     = var.project
    Environment = local.infra.environment
    ManagedBy   = "terraform"
  }
}
