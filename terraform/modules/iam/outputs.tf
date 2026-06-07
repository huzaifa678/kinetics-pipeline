output "hyperpod_execution_role_arn" {
  description = "HyperPod execution role ARN."
  value       = aws_iam_role.hyperpod_execution.arn
}

output "ack_sagemaker_role_arn" {
  description = "Pod Identity role ARN for the ACK SageMaker controller."
  value       = aws_iam_role.ack_sagemaker.arn
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
