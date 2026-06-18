output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_tls" {
  description = <<-EOT
    TLS bootstrap broker list (port 9094). Feed this to Seldon's
    config.kafkaConfig.bootstrap in the CD repo when enable_msk is on.
  EOT
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "security_group_id" {
  description = "Security group attached to the brokers."
  value       = aws_security_group.msk.id
}
