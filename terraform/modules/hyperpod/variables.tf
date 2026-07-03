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

variable "enable_gpu_autoscaling" {
  description = <<-EOT
    Enable HyperPod managed Karpenter autoscaling for the GPU instance groups.
    When true: the cluster runs in Continuous provisioning mode, GPU groups are
    created per-AZ at count 0, and Karpenter scales them on pending GPU pods
    (scale-to-zero). When false: a single fixed-count group sized by
    gpu_instance_count (the legacy manual / scale-gpus.sh path).
  EOT
  type        = bool
  default     = true
}

variable "autoscaler_role_arn" {
  description = "Cluster role HyperPod assumes for Karpenter autoscaling (required when enable_gpu_autoscaling = true)."
  type        = string
  default     = ""
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


variable "gpu_instance_type" {
  description = "GPU instance type for the training group."
  type        = string
}

variable "system_instance_type" {
  description = "Instance type for the always-on NON-GPU HyperPod system group (hosts the training-operator controller). Must be a HyperPod ml.* type the account has 'for cluster usage' quota for (default ml.m5.xlarge — many accounts have ml.m5/ml.t3 quota by default but 0 for ml.c5/ml.g5)."
  type        = string
  default     = "ml.m5.xlarge"
}

variable "system_instance_count" {
  description = "Count for the HyperPod system instance group. 1 = give the operator controller a real HyperPod node; 0 = disable (operator stays DEGRADED until a GPU node exists)."
  type        = number
  default     = 1
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
