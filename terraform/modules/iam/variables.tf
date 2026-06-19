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

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
