variable "cluster_name" {
  description = "EKS cluster name (target for Pod Identity associations)."
  type        = string
}

variable "manage_incluster_addons" {
  description = "Manage the in-cluster APP layer (cert-manager, LB controller, external-dns + the cert-manager-dependent HyperPod operator addons) from Terraform. Set false to let GitOps own them. AWS-API resources (Pod Identity, IAM) are unaffected. ArgoCD itself is gated separately by manage_argocd."
  type        = bool
  default     = true
}

variable "manage_argocd" {
  description = "Manage the ArgoCD bootstrap layer (ArgoCD Helm release, the in-cluster env Secret, and the app-of-apps) from Terraform. Requires cluster API reachability (the VPC self-hosted runner). When false, ArgoCD is bootstrapped out-of-band (gitops/bootstrap). Independent of manage_incluster_addons, which stays false for the app layer."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name stamped on the ArgoCD in-cluster Secret's `environment` label — the ApplicationSet clusters generator uses it to pick the gitops/environments/<env> overlay."
  type        = string
  default     = "dev"
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

# ---------------------------------------------------------------------------
# Inference ingress (AWS LB Controller + external-dns) and AWS-managed
# observability Pod Identity wiring. All gated; empty ARN / false = not created.
# ---------------------------------------------------------------------------
variable "region" {
  description = "AWS region (for the LB controller + external-dns)."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID the AWS Load Balancer Controller provisions ALBs in."
  type        = string
  default     = ""
}

variable "enable_aws_lb_controller" {
  description = "Install the AWS Load Balancer Controller."
  type        = bool
  default     = false
}

variable "enable_external_dns" {
  description = "Install external-dns."
  type        = bool
  default     = false
}

variable "aws_lbc_role_arn" {
  description = "Pod Identity role ARN for the AWS Load Balancer Controller."
  type        = string
  default     = ""
}

variable "external_dns_role_arn" {
  description = "Pod Identity role ARN for external-dns."
  type        = string
  default     = ""
}

variable "external_dns_domain_filter" {
  description = "Domain external-dns is restricted to (e.g. the inference FQDN/zone). Empty = unrestricted."
  type        = string
  default     = ""
}

variable "amp_remote_write_role_arn" {
  description = "Pod Identity role ARN for in-cluster Prometheus -> AMP remote_write (may be unknown at plan)."
  type        = string
  default     = ""
}

variable "otel_xray_role_arn" {
  description = "Pod Identity role ARN for the otel-collector -> X-Ray (may be unknown at plan)."
  type        = string
  default     = ""
}

# Bools known at plan time — used to gate the Pod Identity association counts
# above (the *_role_arn values are created in the same apply and are unknown at
# plan, so they can't gate count directly).
variable "enable_managed_prometheus" {
  description = "Associate the in-cluster Prometheus SA with the AMP remote_write role."
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Associate the otel-collector SA with the X-Ray role."
  type        = bool
  default     = false
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

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
