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
# NOTE: ECR + the OIDC provider and tf/ecr CI roles moved to the bootstrap stack
# (terraform/bootstrap). Their outputs live there now — see bootstrap/outputs.tf.

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

output "msk_bootstrap_brokers_tls" {
  description = "MSK TLS bootstrap brokers (null when enable_msk is off). Feed into the CD repo's seldon-core-v2-runtime kafkaConfig.bootstrap."
  value       = var.enable_msk ? module.msk[0].bootstrap_brokers_tls : null
}

# ---------------------------------------------------------------------------
# Inference ingress + AWS-managed observability.
# ---------------------------------------------------------------------------
output "inference_certificate_arn" {
  description = "ACM cert ARN for the inference ALB (null when no domain configured). Usually NOT needed — the AWS LB Controller auto-discovers the cert by host; exposed for pinning/debug."
  value       = var.inference_domain_name != "" ? aws_acm_certificate.inference[0].arn : null
}

output "inference_host" {
  description = "Internal inference endpoint FQDN (the configured domain; null when unset). Used by scripts/sync-gitops-values.sh to enable the inference Ingress."
  value       = var.inference_domain_name != "" ? var.inference_domain_name : null
}

output "inference_api_host" {
  description = "Public inference API FQDN for prod (api_domain_name; null when unset)."
  value       = var.api_domain_name != "" ? var.api_domain_name : null
}

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID (null when disabled)."
  value       = module.observability.amp_workspace_id
}

output "amp_remote_write_url" {
  description = "AMP remote_write URL — set as prometheus.prometheusSpec.remoteWrite[].url in the CD repo's kube-prometheus-stack values (null when disabled)."
  value       = module.observability.amp_remote_write_url
}

output "amp_query_url" {
  description = "AMP query endpoint base URL (null when disabled)."
  value       = module.observability.amp_query_url
}

output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace endpoint (null when disabled). Requires SSO/SAML to log in."
  value       = module.observability.grafana_workspace_endpoint
}

# ---------------------------------------------------------------------------
# Public inference frontend (Cognito + SPA + WAF).
# ---------------------------------------------------------------------------
output "cognito_issuer" {
  description = "Cognito JWT issuer — set COGNITO_ISSUER on the edge + VITE_COGNITO_AUTHORITY in the SPA (null when disabled)."
  value       = var.enable_cognito ? module.cognito[0].issuer : null
}

output "cognito_hosted_ui_url" {
  description = "Cognito Hosted-UI base URL (null when disabled)."
  value       = var.enable_cognito ? module.cognito[0].hosted_ui_url : null
}

output "cognito_spa_client_id" {
  description = "Public SPA app-client ID — VITE_COGNITO_CLIENT_ID (null when disabled)."
  value       = var.enable_cognito ? module.cognito[0].spa_client_id : null
}

output "cognito_machine_client_id" {
  description = "Machine (client-credentials) app-client ID (null when disabled)."
  value       = var.enable_cognito ? module.cognito[0].machine_client_id : null
}

output "cognito_machine_client_secret" {
  description = "Machine app-client secret (sensitive; null when disabled)."
  value       = var.enable_cognito ? module.cognito[0].machine_client_secret : null
  sensitive   = true
}

output "spa_url" {
  description = "Public SPA URL (null when the frontend is disabled)."
  value       = var.enable_frontend ? module.frontend[0].spa_url : null
}

output "spa_bucket" {
  description = "S3 bucket CI syncs the SPA build to (null when disabled)."
  value       = var.enable_frontend ? module.frontend[0].spa_bucket : null
}

output "cloudfront_distribution_id" {
  description = "SPA CloudFront distribution ID for cache invalidation (null when disabled)."
  value       = var.enable_frontend ? module.frontend[0].cloudfront_distribution_id : null
}

output "frontend_deploy_role_arn" {
  description = "GitHub Actions role for frontend-deploy.yml (AWS_ROLE_FRONTEND_DEPLOY; null when the frontend is disabled)."
  value       = local.frontend_deploy_enabled ? aws_iam_role.frontend_deploy[0].arn : null
}

output "inference_api_waf_arn" {
  description = "Regional WAF ACL ARN for the public inference ALB — set as the Ingress wafv2-acl-arn annotation (null when disabled)."
  value       = var.enable_waf && var.api_domain_name != "" ? aws_wafv2_web_acl.inference_api[0].arn : null
}
