variable "name" {
  description = "Cluster name / prefix."
  type        = string
}

variable "eks_cluster_arn" {
  description = "ARN of the EKS cluster acting as the HyperPod orchestrator."
  type        = string
}

variable "execution_role_arn" {
  description = "HyperPod execution role ARN."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for HyperPod nodes."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for HyperPod nodes (share the EKS node SG)."
  type        = list(string)
}

variable "lifecycle_bucket" {
  description = "S3 bucket name holding the node lifecycle scripts."
  type        = string
}

variable "lifecycle_bucket_arn" {
  description = "ARN of the lifecycle-script bucket."
  type        = string
}

variable "gpu_instance_type" {
  description = "GPU instance type for the training group."
  type        = string
}

variable "gpu_instance_count" {
  description = "Number of GPU nodes (0 = scale-to-zero)."
  type        = number
}

variable "gpu_threads_per_core" {
  description = "Threads per core."
  type        = number
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
