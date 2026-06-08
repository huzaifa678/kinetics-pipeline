output "endpoint_id" {
  description = "Client VPN endpoint ID."
  value       = aws_ec2_client_vpn_endpoint.this.id
}

output "dns_name" {
  description = "DNS name clients connect to (from the downloaded .ovpn config)."
  value       = aws_ec2_client_vpn_endpoint.this.dns_name
}

output "self_service_portal_url" {
  description = "Self-service portal URL (only when a self-service SAML provider is configured)."
  value       = local.enable_self_service ? "https://self-service.clientvpn.amazonaws.com/endpoints/${aws_ec2_client_vpn_endpoint.this.id}" : null
}

output "security_group_id" {
  description = "Security group attached to the Client VPN ENIs."
  value       = aws_security_group.this.id
}

output "client_cidr_block" {
  description = "CIDR assigned to VPN clients (source range for in-VPC access rules)."
  value       = var.client_cidr_block
}
