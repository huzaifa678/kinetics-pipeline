output "region" {
  description = "AWS region."
  value       = var.region
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "hyperpod_cluster_name" {
  description = "SageMaker HyperPod cluster name."
  value       = module.hyperpod.cluster_name
}

output "hyperpod_gpu_instance_group" {
  description = "Name of the GPU instance group (scale this to 0 when idle)."
  value       = module.hyperpod.gpu_instance_group_name
}

output "scale_gpus_up_command" {
  description = "Example AWS CLI to scale the GPU group up for a training run."
  value       = "aws sagemaker update-cluster --cluster-name ${module.hyperpod.cluster_name} --instance-groups 2 --region ${var.region}"
}

output "data_bucket" {
  description = "S3 bucket for input datasets."
  value       = module.storage.data_bucket_name
}

output "checkpoint_bucket" {
  description = "S3 bucket for training checkpoints."
  value       = module.storage.checkpoint_bucket_name
}

output "monthly_budget_usd" {
  description = "Configured monthly budget ceiling."
  value       = var.monthly_budget_usd
}

output "client_vpn_endpoint_id" {
  description = "Client VPN endpoint ID (null when disabled)."
  value       = var.enable_client_vpn ? module.client_vpn[0].endpoint_id : null
}

output "client_vpn_self_service_url" {
  description = "Self-service portal URL to download the VPN client config (null unless configured)."
  value       = var.enable_client_vpn ? module.client_vpn[0].self_service_portal_url : null
}
