output "cluster_name" {
  description = "HyperPod cluster name."
  value       = awscc_sagemaker_cluster.this.cluster_name
}

output "cluster_arn" {
  description = "HyperPod cluster ARN."
  value       = awscc_sagemaker_cluster.this.cluster_arn
}

output "gpu_instance_group_name" {
  description = "Name of the GPU training instance group."
  value       = local.gpu_group_name
}
