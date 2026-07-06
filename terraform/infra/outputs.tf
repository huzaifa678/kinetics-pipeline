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

# ---------------------------------------------------------------------------
# Consumed by the CLUSTER layer (terraform/cluster) via terraform_remote_state:
# provider auth (CA) + everything module.addons/argocd needs that this layer
# creates (IAM role ARNs, cluster/hyperpod ARNs, the enable flags that gate both
# the IAM roles here and the Pod Identity associations there).
# ---------------------------------------------------------------------------
output "eks_cluster_certificate_authority_data" {
  description = "Base64 cluster CA — for the cluster layer's kubernetes/helm/kubectl provider auth."
  value       = module.eks.cluster_certificate_authority_data
}

output "environment" {
  description = "Environment name (stamped on the ArgoCD in-cluster Secret label by the cluster layer)."
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID (passthrough from the network layer; AWS Load Balancer Controller provisions ALBs here)."
  value       = local.network.vpc_id
}

output "name" {
  description = "Resource name prefix (<project>-<environment>) — used by the runner layer."
  value       = local.name
}

output "private_subnet_ids" {
  description = "Private subnet IDs (passthrough from the network layer; NAT egress)."
  value       = local.network.private_subnet_ids
}

output "hyperpod_cluster_arn" {
  description = "HyperPod cluster ARN — gates the operator EKS add-on in the cluster layer. Empty when enable_hyperpod=false (cold-start phase)."
  value       = var.enable_hyperpod ? module.hyperpod[0].cluster_arn : ""
}

output "external_dns_domain_filter" {
  description = "Domain external-dns is restricted to (the effective inference host — api_domain_name in prod, else inference_domain_name; empty = unrestricted)."
  value       = local.inference_effective_host
}

# Pod Identity role ARNs (module.iam) the cluster layer's addons associate to SAs.
output "ack_sagemaker_role_arn" { value = module.iam.ack_sagemaker_role_arn }
output "karpenter_role_arn" { value = module.iam.karpenter_role_arn }
output "etl_shards_role_arn" { value = module.iam.etl_shards_role_arn }
output "image_updater_role_arn" { value = module.iam.image_updater_role_arn }
output "aws_lbc_role_arn" { value = module.iam.aws_lbc_role_arn }
output "external_dns_role_arn" { value = module.iam.external_dns_role_arn }
output "amp_remote_write_role_arn" { value = module.iam.amp_remote_write_role_arn }
output "otel_xray_role_arn" { value = module.iam.otel_xray_role_arn }

# Enable flags that gate BOTH the IAM roles here and the Pod Identity
# associations in the cluster layer — output so the two layers can't drift.
output "enable_aws_lb_controller" { value = var.enable_aws_lb_controller }
output "enable_external_dns" { value = var.enable_external_dns }
output "enable_managed_prometheus" { value = var.enable_managed_prometheus }
output "enable_xray_tracing" { value = var.enable_xray_tracing }

# The CI deployer principals (also mapped to the ci-deployers access entry here);
# the cluster layer reads this to gate module.ci_deployer_rbac without duplication.
output "cluster_deployer_principal_arns" { value = var.cluster_deployer_principal_arns }

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "hyperpod_cluster_name" {
  description = "SageMaker HyperPod cluster name (null when enable_hyperpod=false)."
  value       = var.enable_hyperpod ? module.hyperpod[0].cluster_name : null
}

output "hyperpod_gpu_instance_groups" {
  description = "GPU instance group names. With autoscaling, copy these into the GitOps HyperpodNodeClass.spec.instanceGroups (null when enable_hyperpod=false)."
  value       = var.enable_hyperpod ? module.hyperpod[0].gpu_instance_group_names : null
}

output "gpu_autoscaling_enabled" {
  description = "Whether GPU capacity is managed by HyperPod Karpenter autoscaling (true) or a fixed group + scale-gpus.sh (false)."
  value       = var.enable_gpu_autoscaling
}

output "scale_gpus_up_command" {
  description = "Manual GPU scaling command — only relevant when enable_gpu_autoscaling = false. With autoscaling on, Karpenter provisions GPU nodes from pending pods automatically."
  value = !var.enable_hyperpod ? "enable_hyperpod=false" : var.enable_gpu_autoscaling ? "GPU autoscaling enabled — submit a HyperPodPyTorchJob and Karpenter provisions nodes; no manual scaling needed." : (
    "aws sagemaker update-cluster --cluster-name ${module.hyperpod[0].cluster_name} --region ${var.region}  # set the gpu-training group InstanceCount"
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

output "msk_bootstrap_brokers_sasl_scram" {
  description = "MSK SASL/SCRAM bootstrap brokers (port 9096; empty unless enable_msk + client_authentication=sasl_scram — the prod posture). Feed to Seldon kafkaConfig.bootstrap."
  value       = var.enable_msk ? module.msk[0].bootstrap_brokers_sasl_scram : null
}

output "msk_scram_secret_arn" {
  description = "Secrets Manager ARN with the SASL/SCRAM username/password (null unless enable_msk + sasl_scram). Bridge to a k8s Secret for Seldon (e.g. External Secrets Operator)."
  value       = var.enable_msk ? module.msk[0].scram_secret_arn : null
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
