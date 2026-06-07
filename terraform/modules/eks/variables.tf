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

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
