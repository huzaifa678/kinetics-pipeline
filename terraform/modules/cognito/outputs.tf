output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "issuer" {
  description = "JWT issuer URL — set as COGNITO_ISSUER on the inference edge, and the OIDC authority in the SPA."
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "jwks_url" {
  description = "JWKS endpoint the edge fetches signing keys from."
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}/.well-known/jwks.json"
}

output "hosted_ui_url" {
  description = "Cognito Hosted-UI base URL (OAuth authorize/token endpoints live under it)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "spa_client_id" {
  description = "Public SPA app-client ID — VITE_COGNITO_CLIENT_ID + the auth allow-list."
  value       = aws_cognito_user_pool_client.spa.id
}

output "machine_client_id" {
  description = "Confidential machine app-client ID (client_credentials)."
  value       = aws_cognito_user_pool_client.machine.id
}

output "machine_client_secret" {
  description = "Machine app-client secret (client_credentials). Sensitive."
  value       = aws_cognito_user_pool_client.machine.client_secret
  sensitive   = true
}

output "predict_scope" {
  description = "Fully-qualified scope for client-credentials token requests (inference/predict)."
  value       = aws_cognito_resource_server.inference.scope_identifiers[0]
}
