variable "name" {
  description = "Name prefix (<project>-<environment>)."
  type        = string
}

variable "hosted_ui_domain_prefix" {
  description = "Cognito Hosted-UI domain prefix (globally unique within the region). Hosted UI = https://<prefix>.auth.<region>.amazoncognito.com."
  type        = string
}

variable "callback_urls" {
  description = "Allowed OAuth callback URLs for the SPA (e.g. https://<frontend-domain>/, http://localhost:5173/ for local dev)."
  type        = list(string)
}

variable "logout_urls" {
  description = "Allowed sign-out redirect URLs for the SPA."
  type        = list(string)
}

variable "backstage_callback_urls" {
  description = "OAuth callback URLs for the Backstage OIDC client (the /api/auth/oidc/handler/frame path). Empty list => no Backstage client is created."
  type        = list(string)
  default     = []
}

variable "backstage_logout_urls" {
  description = "Sign-out redirect URLs for the Backstage OIDC client."
  type        = list(string)
  default     = []
}

variable "allow_self_signup" {
  description = "Allow users to self-register in the Hosted UI. Default false = admins provision users (safer for a prod endpoint)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
