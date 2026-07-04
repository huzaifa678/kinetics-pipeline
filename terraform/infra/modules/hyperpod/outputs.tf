output "cluster_name" {
  description = "HyperPod cluster name."
  value       = awscc_sagemaker_cluster.this.cluster_name
}

output "cluster_arn" {
  description = "HyperPod cluster ARN."
  value       = awscc_sagemaker_cluster.this.cluster_arn
}

output "gpu_instance_group_names" {
  description = "Names of the GPU training instance groups (one per AZ when autoscaling). Feed these into the GitOps HyperpodNodeClass.spec.instanceGroups."
  value       = local.gpu_group_names
}

output "gpu_instance_group_name" {
  description = "Primary GPU instance group name (first group). Kept for the cost auto-stop Lambda / legacy fixed-count path."
  value       = local.gpu_group_names[0]
}
