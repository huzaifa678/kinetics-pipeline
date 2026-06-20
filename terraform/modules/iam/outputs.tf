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

output "karpenter_node_role_arn" {
  description = "EC2 node role ARN Karpenter assigns to provisioned nodes."
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_role_name" {
  description = "EC2 node role name (referenced by Karpenter EC2NodeClass)."
  value       = aws_iam_role.karpenter_node.name
}
