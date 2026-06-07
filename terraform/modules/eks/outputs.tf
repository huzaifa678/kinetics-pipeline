output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN (used as the HyperPod orchestrator)."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA cert."
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "IRSA OIDC provider URL (no https:// prefix)."
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Security group shared by nodes (attached to HyperPod nodes too)."
  value       = module.eks.node_security_group_id
}
