# Config for the cluster layer. Cluster connection, IAM role ARNs, the CI deployer
# principals, and the enable flags shared with infra all come from remote state —
# these are the knobs that are purely "how to configure the in-cluster layer".

variable "project" {
  description = "Project name (tags only; the infra layer owns naming)."
  type        = string
  default     = "kinetics-pipeline"
}

variable "manage_argocd" {
  description = "Manage the ArgoCD bootstrap layer + the ci-deployer RBAC + the deps check. Requires cluster API reachability (VPC runner / VPN)."
  type        = bool
  default     = true
}

variable "manage_incluster_addons" {
  description = "Manage the app-layer in-cluster add-ons (cert-manager, LB controller, external-dns + HyperPod operator EKS add-ons) from Terraform. False = GitOps-owned."
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Install ArgoCD and bootstrap the app-of-apps."
  type        = bool
  default     = true
}

variable "enable_hyperpod_operator" {
  description = "Create the HyperPod training operator EKS add-on (installs cert-manager first)."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Git repo ArgoCD watches."
  type        = string
  default     = "https://github.com/huzaifa678/Kinetics-Continious-Delivery.git"
}

variable "gitops_repo_revision" {
  description = "Git revision ArgoCD tracks."
  type        = string
  default     = "main"
}

variable "aws_lb_controller_chart_version" {
  description = "aws-load-balancer-controller Helm chart version."
  type        = string
  default     = "1.13.3"
}

variable "external_dns_chart_version" {
  description = "external-dns Helm chart version."
  type        = string
  default     = "1.15.2"
}
