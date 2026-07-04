variable "name" {
  description = "Name prefix (project-environment)."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the runner in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the runner ASG (egress via NAT = the EKS-allowed EIP)."
  type        = list(string)
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo the runner registers to."
  type        = string
}

variable "github_repo" {
  description = "Repo the runner registers to."
  type        = string
}

variable "runner_labels" {
  description = "Labels the runner advertises; workflows target these via runs-on."
  type        = string
  default     = "self-hosted,linux,vpc"
}

variable "instance_type" {
  description = "Runner instance type. It only runs terraform + kubectl/helm, so small is fine."
  type        = string
  default     = "t3.small"
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
