output "hyperpod_execution_role_arn" {
  description = "HyperPod execution role ARN."
  value       = aws_iam_role.hyperpod_execution.arn
}

output "hyperpod_execution_role_name" {
  description = "HyperPod execution role name (for attaching extra policies, e.g. MLflow access)."
  value       = aws_iam_role.hyperpod_execution.name
}

output "hyperpod_autoscaler_role_arn" {
  description = "Cluster role assumed by HyperPod for Karpenter-based node autoscaling."
  value       = aws_iam_role.hyperpod_autoscaler.arn
}

output "ack_sagemaker_role_arn" {
  description = "Pod Identity role ARN for the ACK SageMaker controller."
  value       = aws_iam_role.ack_sagemaker.arn
}

output "etl_shards_role_arn" {
  description = "Pod Identity role ARN for the ETL shard-build Job (S3 write)."
  value       = aws_iam_role.etl_shards.arn
}

output "image_updater_role_arn" {
  description = "Pod Identity role ARN for the ArgoCD Image Updater (ECR read)."
  value       = aws_iam_role.image_updater.arn
}

output "karpenter_role_arn" {
  description = "Pod Identity role ARN for the Karpenter controller."
  value       = aws_iam_role.karpenter_controller.arn
}

output "external_secrets_role_arn" {
  description = "Pod Identity role ARN for the External Secrets controller"
  value       = aws_iam_role.external_secrets.arn
}

output "keda_metrics_role_arn" {
  description = "Pod Identity role ARN for the KEDA AMP-trigger fallback (empty when AMP is off)."
  value       = var.enable_managed_prometheus ? aws_iam_role.keda_amp[0].arn : ""
}

output "karpenter_node_role_arn" {
  description = "EC2 node role ARN Karpenter assigns to provisioned nodes."
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_role_name" {
  description = "EC2 node role name (referenced by Karpenter EC2NodeClass)."
  value       = aws_iam_role.karpenter_node.name
}

output "amp_remote_write_role_arn" {
  description = "Pod Identity role ARN for in-cluster Prometheus -> AMP remote_write (empty when AMP is off)."
  value       = var.amp_workspace_arn != "" ? aws_iam_role.amp_remote_write[0].arn : ""
}

output "otel_xray_role_arn" {
  description = "Pod Identity role ARN for the otel-collector -> X-Ray (empty when X-Ray tracing is off)."
  value       = var.enable_xray_tracing ? aws_iam_role.otel_xray[0].arn : ""
}

output "aws_lbc_role_arn" {
  description = "Pod Identity role ARN for the AWS Load Balancer Controller (empty when off)."
  value       = var.enable_aws_lb_controller ? aws_iam_role.aws_lbc[0].arn : ""
}

output "external_dns_role_arn" {
  description = "Pod Identity role ARN for external-dns (empty when off)."
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : ""
}
