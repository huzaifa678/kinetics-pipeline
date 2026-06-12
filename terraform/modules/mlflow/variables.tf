variable "name" {
  description = "Name prefix."
  type        = string
}

variable "tracking_server_size" {
  description = "Managed MLflow tracking server size: Small | Medium | Large. Small is cheapest."
  type        = string
  default     = "Small"
}

variable "mlflow_version" {
  description = "MLflow version for the managed tracking server. Empty = let SageMaker pick the latest supported version (recommended)."
  type        = string
  default     = ""
}

variable "automatic_model_registration" {
  description = "Auto-register logged models into the SageMaker Model Registry."
  type        = bool
  default     = false
}

variable "trainer_role_name" {
  description = "Name of the trainer IAM role (HyperPod execution role) to grant MLflow log access. Empty skips the grant."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
