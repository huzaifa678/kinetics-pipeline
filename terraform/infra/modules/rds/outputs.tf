output "db_endpoint" {
  description = "Postgres endpoint host (no port)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Postgres port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "The DB security group id."
  value       = aws_security_group.this.id
}

output "secret_arn" {
  description = "Secrets Manager ARN holding the connection JSON (synced into the cluster by ESO)."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secrets Manager name (the ExternalSecret remoteRef.key)."
  value       = aws_secretsmanager_secret.db.name
}
