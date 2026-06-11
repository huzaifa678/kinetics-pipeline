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

output "hyperpod_gpu_instance_groups" {
  description = "GPU instance group names. With autoscaling, copy these into the GitOps HyperpodNodeClass.spec.instanceGroups."
  value       = module.hyperpod.gpu_instance_group_names
}

output "gpu_autoscaling_enabled" {
  description = "Whether GPU capacity is managed by HyperPod Karpenter autoscaling (true) or a fixed group + scale-gpus.sh (false)."
  value       = var.enable_gpu_autoscaling
}

output "scale_gpus_up_command" {
  description = "Manual GPU scaling command — only relevant when enable_gpu_autoscaling = false. With autoscaling on, Karpenter provisions GPU nodes from pending pods automatically."
  value = var.enable_gpu_autoscaling ? "GPU autoscaling enabled — submit a HyperPodPyTorchJob and Karpenter provisions nodes; no manual scaling needed." : (
    "aws sagemaker update-cluster --cluster-name ${module.hyperpod.cluster_name} --region ${var.region}  # set the gpu-training group InstanceCount"
  )
}

output "data_bucket" {
  description = "S3 bucket for input datasets."
  value       = module.storage.data_bucket_name
}

output "checkpoint_bucket" {
  description = "S3 bucket for training checkpoints."
  value       = module.storage.checkpoint_bucket_name
}

# ---------------------------------------------------------------------------
# Container registry + CI/CD role ARNs (set these as GitHub repo variables).
# ---------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "ECR repository URL — the image.repository for the training chart (GitHub var: ECR_REPOSITORY)."
  value       = module.ecr.repository_url
}

output "gha_ecr_push_role_arn" {
  description = "GitHub Actions role for docker-build.yml (GitHub var: AWS_ROLE_ECR_PUSH)."
  value       = var.enable_github_oidc ? module.cicd[0].ecr_push_role_arn : null
}

output "gha_terraform_plan_role_arn" {
  description = "GitHub Actions role for terraform-plan.yml (GitHub var: AWS_ROLE_TF_PLAN)."
  value       = var.enable_github_oidc ? module.cicd[0].terraform_plan_role_arn : null
}

output "gha_terraform_apply_role_arn" {
  description = "GitHub Actions role for terraform-apply.yml (GitHub var: AWS_ROLE_TF_APPLY)."
  value       = var.enable_github_oidc ? module.cicd[0].terraform_apply_role_arn : null
}

output "monthly_budget_usd" {
  description = "Configured monthly budget ceiling."
  value       = var.monthly_budget_usd
}

output "mlflow_tracking_server_arn" {
  description = "SageMaker MLflow tracking server ARN. Set as MLFLOW_TRACKING_URI / --mlflow-tracking-uri (null when enable_mlflow=false)."
  value       = var.enable_mlflow ? module.mlflow[0].tracking_server_arn : null
}

output "mlflow_artifact_bucket" {
  description = "S3 bucket backing the MLflow artifact store (null when enable_mlflow=false)."
  value       = var.enable_mlflow ? module.mlflow[0].artifact_bucket_name : null
}

output "client_vpn_endpoint_id" {
  description = "Client VPN endpoint ID (null when disabled)."
  value       = var.enable_client_vpn ? module.client_vpn[0].endpoint_id : null
}

output "client_vpn_self_service_url" {
  description = "Self-service portal URL to download the VPN client config (null unless configured)."
  value       = var.enable_client_vpn ? module.client_vpn[0].self_service_portal_url : null
}
