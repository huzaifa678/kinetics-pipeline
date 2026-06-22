variable "name" {
  description = "Name prefix."
  type        = string
}

variable "enable_managed_prometheus" {
  description = "Create the AMP workspace."
  type        = bool
  default     = false
}

variable "enable_managed_grafana" {
  description = "Create the AMG workspace (+ its query role). Requires SSO/SAML to log in."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
