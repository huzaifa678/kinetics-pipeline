output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap brokers (port 9094, no client auth) — for the unauthenticated dev posture."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "bootstrap_brokers_sasl_scram" {
  description = "SASL/SCRAM bootstrap brokers (port 9096; empty unless client_authentication=sasl_scram). Feed to Seldon's kafkaConfig.bootstrap for prod."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_scram
}

output "bootstrap_brokers_sasl_iam" {
  description = "SASL/IAM bootstrap brokers (port 9098; empty unless client_authentication=iam)."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "scram_secret_arn" {
  description = "Secrets Manager ARN with the SASL/SCRAM username/password (null unless sasl_scram). Bridge to a k8s Secret for Seldon (e.g. External Secrets Operator)."
  value       = local.scram ? aws_secretsmanager_secret.scram[0].arn : null
}

output "security_group_id" {
  description = "Security group attached to the brokers."
  value       = aws_security_group.msk.id
}
