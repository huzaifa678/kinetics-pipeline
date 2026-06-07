variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix and tag on all resources."
  type        = string
  default     = "kinetics-pipeline"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "EKS control-plane Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "system_node_instance_type" {
  description = "Instance type for the small, always-on CPU system node group (controllers, ArgoCD, etc.)."
  type        = string
  default     = "m6i.large"
}

variable "system_node_desired_size" {
  description = "Desired size of the CPU system node group."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# HyperPod GPU training cluster
# ---------------------------------------------------------------------------
variable "gpu_instance_type" {
  description = "GPU instance type for the HyperPod training instance group (e.g. ml.g5.12xlarge, ml.g6e.12xlarge, ml.p5.48xlarge)."
  type        = string
  default     = "ml.g5.12xlarge"
}

variable "gpu_instance_count" {
  description = <<-EOT
    Number of GPU nodes in the HyperPod training instance group.
    COST CONTROL: defaults to 0 (scale-to-zero) so you never pay for idle GPUs.
    Set to N only while a training run is active, then return to 0.
  EOT
  type        = number
  default     = 0
}

variable "gpu_threads_per_core" {
  description = "Threads per core for GPU nodes. Set to 1 to disable hyperthreading for training workloads."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Cost guardrails
# ---------------------------------------------------------------------------
variable "monthly_budget_usd" {
  description = "Hard monthly cost budget in USD. Alerts fire at 50/80/100% of this."
  type        = number
  default     = 100
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget + anomaly alerts."
  type        = list(string)
  default     = []
}

variable "auto_stop_idle_minutes" {
  description = "Scale GPU instance group to 0 after this many minutes with no active training job. 0 disables the auto-stop guard."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "fsx_storage_capacity_gb" {
  description = "FSx for Lustre capacity in GiB (provisioned, billed). Size to your working set; tear down when idle."
  type        = number
  default     = 1200
}

variable "checkpoint_retention_days" {
  description = "Days before old checkpoints transition to S3 Infrequent Access, then expire."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# GitOps
# ---------------------------------------------------------------------------
variable "enable_argocd" {
  description = "Install ArgoCD and bootstrap the app-of-apps for GitOps-managed workloads."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Git repository URL that ArgoCD watches for application manifests."
  type        = string
  default     = ""
}

variable "gitops_repo_revision" {
  description = "Git revision (branch/tag) ArgoCD tracks."
  type        = string
  default     = "main"
}
