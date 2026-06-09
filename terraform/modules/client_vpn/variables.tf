variable "name" {
  description = "Name / prefix for the Client VPN resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC the Client VPN attaches to."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — authorized for VPN clients and used to derive the default DNS resolver."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    Subnets to associate the Client VPN with. Use the PRIVATE subnets so client
    internet-bound traffic egresses through the VPC NAT gateway (the EIP the EKS
    public endpoint is locked to), and so the EKS private endpoint is reachable.
  EOT
  type        = list(string)
}

variable "client_cidr_block" {
  description = <<-EOT
    IPv4 CIDR for VPN clients. Must NOT overlap the VPC CIDR (or any routed
    network), and must be at least a /22.
  EOT
  type        = string
  default     = "10.100.0.0/22"
}

variable "saml_metadata_document" {
  description = <<-EOT
    SAML IdP metadata XML for the AWS Client VPN app you created in IAM Identity
    Center. Pass the file contents, e.g. file("client-vpn-saml-metadata.xml").
  EOT
  type        = string
}

variable "self_service_saml_metadata_document" {
  description = <<-EOT
    Optional SAML metadata for the self-service portal app (lets users download
    the client config from a portal). Empty disables the self-service portal.
  EOT
  type        = string
  default     = ""
}

variable "saml_application_arn" {
  description = <<-EOT
    IAM Identity Center custom SAML app ARN for the Client VPN (created in the
    console). When set, the users/groups below are assigned to it in Terraform so
    they can authenticate to the VPN — replaces the manual
    `aws sso-admin create-application-assignment` step. Empty disables management.
  EOT
  type        = string
  default     = ""
}

variable "saml_assignment_user_names" {
  description = "Identity Center usernames to assign to the Client VPN SAML app."
  type        = list(string)
  default     = []
}

variable "saml_assignment_group_display_names" {
  description = "Identity Center group display names to assign to the Client VPN SAML app."
  type        = list(string)
  default     = []
}

variable "server_certificate_arn" {
  description = <<-EOT
    ACM ARN of an existing server certificate. Leave empty to have this module
    generate and import a self-signed server certificate.
  EOT
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = <<-EOT
    DNS servers pushed to VPN clients. Empty defaults to the VPC resolver
    (VPC CIDR base + 2) so in-VPC names — including the EKS private endpoint —
    resolve to private IPs while connected.
  EOT
  type        = list(string)
  default     = []
}

variable "split_tunnel" {
  description = <<-EOT
    Split tunnel: only routes for authorized networks (the VPC) go through the
    VPN; the rest uses the client's local connection. Recommended (true). Set
    false for full-tunnel so ALL client traffic egresses via the NAT EIP.
  EOT
  type        = bool
  default     = true
}

variable "authorize_internet" {
  description = <<-EOT
    Also add a 0.0.0.0/0 route + authorization so clients reach the internet
    through the VPC NAT gateway. Needed only if you want the EKS *public*
    endpoint reachable over the VPN (the private endpoint path does not need it).
  EOT
  type        = bool
  default     = false
}

variable "session_timeout_hours" {
  description = "Max VPN session duration before re-auth. One of 8, 10, 12, 24."
  type        = number
  default     = 8
}

variable "transport_protocol" {
  description = "Transport protocol for the VPN tunnel (udp or tcp)."
  type        = string
  default     = "udp"
}

variable "enable_connection_logging" {
  description = "Stream connection logs to the given CloudWatch Logs group (created here when true)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
