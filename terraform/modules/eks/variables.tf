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

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the public EKS API endpoint. The root passes the
    VPC NAT gateway EIP (AWS Client VPN egress) here plus any extra CIDRs. This is
    a NETWORK control only — authn/authz is still handled by IAM access entries
    (see cluster_admin_principal_arns). Must be non-empty.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_hyperpod_operator" {
  description = "Install the SageMaker HyperPod training operator EKS add-on. Turn off for a minimal/test EKS-only cluster."
  type        = bool
  default     = true
}

variable "vpn_client_cidr_block" {
  description = <<-EOT
    Client VPN client CIDR allowed to reach the cluster API server SG on 443
    (so on-VPN kubectl/Terraform reach the private endpoint). Empty disables the
    rule.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
