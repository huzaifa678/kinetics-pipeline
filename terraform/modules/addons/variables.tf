variable "name" {
  description = "Name prefix."
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

variable "etl_shards_role_arn" {
  description = "Pod Identity role ARN for the ETL shard-build Job (S3 write)."
  type        = string
}

variable "etl_shards_namespace" {
  description = "Namespace the ETL shard Job runs in (must match where you apply it)."
  type        = string
  default     = "default"
}

variable "image_updater_role_arn" {
  description = "Pod Identity role ARN for the ArgoCD Image Updater (ECR read)."
  type        = string
}

variable "enable_argocd" {
  description = "Install ArgoCD and bootstrap the app-of-apps."
  type        = bool
  default     = true
}

variable "enable_hyperpod_operator" {
  description = "Create the HyperPod training operator EKS add-on (installs cert-manager first as its prerequisite)."
  type        = bool
  default     = true
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version (prerequisite of the HyperPod operator add-on)."
  type        = string
  default     = "v1.20.2"
}

variable "hyperpod_cluster_arn" {
  description = "HyperPod cluster ARN — gates the operator add-on so it isn't created until the cluster (its system node) exists. Empty when the operator is disabled."
  type        = string
  default     = ""
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

variable "argocd_version" {
  description = "argo-cd Helm chart version (bootstrap)."
  type        = string
  default     = "7.7.0"
}

variable "argocd_apps_version" {
  description = "argocd-apps Helm chart version (deploys the app-of-apps root Application). Verify against current chart releases."
  type        = string
  default     = "2.0.2"
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
