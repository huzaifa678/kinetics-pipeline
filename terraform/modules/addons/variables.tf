variable "name" {
  description = "Name prefix."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (target for Pod Identity associations)."
  type        = string
}

variable "ack_sagemaker_role_arn" {
  description = "Pod Identity role ARN for the ACK SageMaker controller."
  type        = string
}

variable "karpenter_role_arn" {
  description = "Pod Identity role ARN for Karpenter."
  type        = string
}

variable "enable_argocd" {
  description = "Install ArgoCD and bootstrap the app-of-apps."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Git repo ArgoCD watches."
  type        = string
  default     = ""
}

variable "gitops_repo_revision" {
  description = "Git revision ArgoCD tracks."
  type        = string
  default     = "main"
}

variable "argocd_version" {
  description = "argo-cd Helm chart version (bootstrap)."
  type        = string
  default     = "7.7.0"
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
