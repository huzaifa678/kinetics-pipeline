variable "name" {
  description = "Name prefix."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used in Karpenter IAM conditions)."
  type        = string
}

variable "data_bucket_arn" {
  description = "Dataset bucket ARN."
  type        = string
}

variable "checkpoint_bucket_arn" {
  description = "Checkpoint bucket ARN."
  type        = string
}

variable "karpenter_interruption_queue_arn" {
  description = "ARN of the Karpenter SQS interruption queue."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repo ARN the ArgoCD Image Updater role may read. Empty = all repos."
  type        = string
  default     = ""
}

variable "amp_workspace_arn" {
  description = "AMP workspace ARN scoping the amp-remote-write role (may be unknown at plan; gate creation on enable_managed_prometheus, not this)."
  type        = string
  default     = ""
}

variable "enable_managed_prometheus" {
  description = "Create the amp-remote-write Pod Identity role. Known at plan time (unlike amp_workspace_arn), so it gates count safely."
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Create the otel-collector -> X-Ray Pod Identity role."
  type        = bool
  default     = false
}

variable "enable_aws_lb_controller" {
  description = "Create the AWS Load Balancer Controller Pod Identity role + policy."
  type        = bool
  default     = false
}

variable "enable_external_dns" {
  description = "Create the external-dns Pod Identity role."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Hosted zone ID to scope the external-dns role to. Empty = all zones."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
