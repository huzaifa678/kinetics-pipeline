# ---------------------------------------------------------------------------
# Amazon Cognito — identity for the public inference endpoint. Two consumers:
#   * the React SPA  -> Hosted-UI login (auth-code + PKCE, public client).
#   * machine clients -> client-credentials (confidential client + secret).
# The FastAPI edge verifies the issued JWT (kinetics_trainer.serving.auth).
# Gated at the root via count (var.enable_cognito).
# ---------------------------------------------------------------------------

data "aws_region" "current" {}

resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Admin-provisioned by default (no open self-signup on a prod endpoint).
  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = var.tags
}

# Hosted UI domain (login page). Full URL:
# https://<prefix>.auth.<region>.amazoncognito.com
resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.hosted_ui_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Custom resource server + scope so machine (client-credentials) tokens carry a
# usable scope (the standard openid/email scopes aren't valid for that flow).
resource "aws_cognito_resource_server" "inference" {
  identifier   = "inference"
  name         = "${var.name}-inference"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "predict"
    scope_description = "Call POST /predict"
  }
}

# Public SPA client — no secret, auth-code + PKCE (Cognito enforces PKCE for
# public clients on the code flow).
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.name}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", aws_cognito_resource_server.inference.scope_identifiers[0]]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  prevent_user_existence_errors = "ENABLED"
}

# Confidential machine client — client-credentials, scoped to inference/predict.
resource "aws_cognito_user_pool_client" "machine" {
  name         = "${var.name}-machine"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = [aws_cognito_resource_server.inference.scope_identifiers[0]]
  supported_identity_providers         = ["COGNITO"]

  # client_credentials is non-interactive: no callback/login flows.
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]
}
