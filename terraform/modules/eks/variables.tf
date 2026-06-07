variable "name" {
  description = "Cluster name / prefix."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the cluster and nodes."
  type        = list(string)
}

variable "system_node_instance_type" {
  description = "Instance type for the CPU system node group."
  type        = string
}

variable "system_node_desired_size" {
  description = "Desired size of the system node group."
  type        = number
}

variable "cluster_admin_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (roles/users) granted cluster-admin via EKS access
    entries (AmazonEKSClusterAdminPolicy). Replaces the implicit cluster-creator
    admin grant. IMPORTANT: set at least one real admin principal (e.g. your SSO
    admin role or a break-glass role) — with creator-admin disabled and this
    empty, NO ONE will have cluster admin.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
