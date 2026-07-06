output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes + HyperPod)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateway(s) — the egress IP for AWS Client VPN clients routed through the VPC."
  value       = module.vpc.nat_public_ips
}
