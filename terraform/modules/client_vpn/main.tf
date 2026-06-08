locals {
  generate_server_cert = var.server_certificate_arn == ""
  server_cert_arn      = local.generate_server_cert ? aws_acm_certificate.server[0].arn : var.server_certificate_arn

  dns_servers = length(var.dns_servers) > 0 ? var.dns_servers : [cidrhost(var.vpc_cidr, 2)]

  enable_self_service = var.self_service_saml_metadata_document != ""
}


resource "tls_private_key" "ca" {
  count     = local.generate_server_cert ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  count             = local.generate_server_cert ? 1 : 0
  private_key_pem   = tls_private_key.ca[0].private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "${var.name}-client-vpn-ca"
    organization = var.name
  }

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "server" {
  count     = local.generate_server_cert ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  count           = local.generate_server_cert ? 1 : 0
  private_key_pem = tls_private_key.server[0].private_key_pem

  subject {
    common_name  = "${var.name}-client-vpn-server"
    organization = var.name
  }
}

resource "tls_locally_signed_cert" "server" {
  count              = local.generate_server_cert ? 1 : 0
  cert_request_pem   = tls_cert_request.server[0].cert_request_pem
  ca_private_key_pem = tls_private_key.ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca[0].cert_pem

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "aws_acm_certificate" "server" {
  count             = local.generate_server_cert ? 1 : 0
  private_key       = tls_private_key.server[0].private_key_pem
  certificate_body  = tls_locally_signed_cert.server[0].cert_pem
  certificate_chain = tls_self_signed_cert.ca[0].cert_pem

  tags = merge(var.tags, { Name = "${var.name}-client-vpn-server" })
}

resource "aws_iam_saml_provider" "this" {
  name                   = "${var.name}-client-vpn"
  saml_metadata_document = var.saml_metadata_document
  tags                   = var.tags
}

resource "aws_iam_saml_provider" "self_service" {
  count                  = local.enable_self_service ? 1 : 0
  name                   = "${var.name}-client-vpn-self-service"
  saml_metadata_document = var.self_service_saml_metadata_document
  tags                   = var.tags
}


resource "aws_security_group" "this" {
  name_prefix = "${var.name}-client-vpn-"
  description = "Client VPN endpoint ENIs"
  vpc_id      = var.vpc_id

  egress {
    description = "All egress into the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-client-vpn" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Optional connection logging.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  count             = var.enable_connection_logging ? 1 : 0
  name              = "/aws/client-vpn/${var.name}"
  retention_in_days = 30
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Client VPN endpoint (federated / SAML auth).
# ---------------------------------------------------------------------------
resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name} Client VPN"
  server_certificate_arn = local.server_cert_arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = var.split_tunnel
  session_timeout_hours  = var.session_timeout_hours
  transport_protocol     = var.transport_protocol
  dns_servers            = local.dns_servers

  vpc_id             = var.vpc_id
  security_group_ids = [aws_security_group.this.id]

  authentication_options {
    type                           = "federated-authentication"
    saml_provider_arn              = aws_iam_saml_provider.this.arn
    self_service_saml_provider_arn = local.enable_self_service ? aws_iam_saml_provider.self_service[0].arn : null
  }

  connection_log_options {
    enabled              = var.enable_connection_logging
    cloudwatch_log_group = var.enable_connection_logging ? aws_cloudwatch_log_group.this[0].name : null
  }

  tags = merge(var.tags, { Name = "${var.name}-client-vpn" })
}

# ---------------------------------------------------------------------------
# Associate with the private subnets (one per AZ for HA).
# ---------------------------------------------------------------------------
resource "aws_ec2_client_vpn_network_association" "this" {
  count = length(var.subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]
}

# ---------------------------------------------------------------------------
# Authorization: allow all SAML-authenticated users to reach the VPC.
# ---------------------------------------------------------------------------
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
}

# ---------------------------------------------------------------------------
# Optional: route + authorize internet (full egress via the VPC NAT gateway).
# One route per associated subnet is required.
# ---------------------------------------------------------------------------
resource "aws_ec2_client_vpn_authorization_rule" "internet" {
  count                  = var.authorize_internet ? 1 : 0
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = "0.0.0.0/0"
  authorize_all_groups   = true
}

resource "aws_ec2_client_vpn_route" "internet" {
  count = var.authorize_internet ? length(var.subnet_ids) : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  destination_cidr_block = "0.0.0.0/0"
  target_vpc_subnet_id   = var.subnet_ids[count.index]

  depends_on = [aws_ec2_client_vpn_network_association.this]
}
