variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag to scope budgets/anomaly detection."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget ceiling in USD."
  type        = number
}

variable "alert_emails" {
  description = "Emails for budget/anomaly/auto-stop alerts."
  type        = list(string)
}

variable "auto_stop_idle_minutes" {
  description = "Idle window + schedule for the auto-stop guard. 0 disables it."
  type        = number
}

variable "hyperpod_cluster_name" {
  description = "HyperPod cluster name the auto-stop Lambda manages."
  type        = string
}

variable "gpu_instance_group" {
  description = "GPU instance group the auto-stop Lambda scales to 0."
  type        = string
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
