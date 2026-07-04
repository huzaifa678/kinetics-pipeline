variable "app_name" {
  description = "Name of the ArgoCD Application that syncs the AWS HyperPod dependency umbrella chart."
  type        = string
  default     = "hyperpod-dependencies"
}

variable "app_namespace" {
  description = "Namespace the ArgoCD Application object lives in (ArgoCD's own namespace, not the chart's target namespace)."
  type        = string
  default     = "argocd"
}
