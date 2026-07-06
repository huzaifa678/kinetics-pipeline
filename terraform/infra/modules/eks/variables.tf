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

variable "cluster_deployer_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (e.g. the CI apply role) that get a NON-admin access entry
    mapped to the k8s group `kinetics:ci-deployers`. No AWS-managed access policy
    is attached — authorization comes from the out-of-band `ci-deployer`
    ClusterRole bound to that group (terraform/rbac/ci-deployer.yaml). This is the
    minimum that can still `helm install` argocd (which creates CRDs + cluster
    RBAC) without granting cluster-admin.
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_viewer_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (e.g. the CI plan role) granted a read-only access entry
    (AmazonEKSAdminViewPolicy — read incl. secrets). Lets `terraform plan` refresh
    in-cluster resources (Helm release secrets, argocd secret, RBAC) without
    cluster-admin or write access.
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_bootstrap_principal_arns" {
  description = <<-EOT
    IAM principal ARNs granted a cluster-admin access entry
    (AmazonEKSClusterAdminPolicy) for the ONE-TIME ci-deployer RBAC + ArgoCD
    bootstrap. Intended to hold only the gated cluster-bootstrap OIDC role
    (assumable solely from the protected GitHub Environment). Kept separate from
    cluster_deployer_principal_arns so the steady-state CI identity never becomes
    cluster-admin. Empty = no such entry.
  EOT
  type        = list(string)
  default     = []
}

variable "deployer_group" {
  description = "Kubernetes group the deployer access entries map to; the ci-deployer ClusterRoleBinding must bind this exact group."
  type        = string
  default     = "kinetics:ci-deployers"
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

variable "vpc_cidr" {
  description = "VPC CIDR — allowed to the cluster API SG on 443 for Client VPN clients (which are SNATed to a VPC subnet IP)."
  type        = string
  default     = "10.0.0.0/16"
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
