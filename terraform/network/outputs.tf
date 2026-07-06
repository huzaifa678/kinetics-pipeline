output "name" {
  description = "Resource name prefix (<project>-<environment>) — consumed by the infra + runner layers."
  value       = local.name
}

output "environment" {
  description = "Environment name — the runner layer stamps it on its tags."
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR — the infra layer reads this for its VPC-scoped SG rules (single source of truth)."
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes + HyperPod; the runner ASG lands here for NAT egress)."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateway(s) — the egress IP allow-listed on the EKS public endpoint and for Client VPN clients."
  value       = module.vpc.nat_public_ips
}
