output "data_bucket_name" {
  description = "Dataset bucket name."
  value       = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  description = "Dataset bucket ARN."
  value       = aws_s3_bucket.data.arn
}

output "checkpoint_bucket_name" {
  description = "Checkpoint bucket name."
  value       = aws_s3_bucket.checkpoints.bucket
}

output "checkpoint_bucket_arn" {
  description = "Checkpoint bucket ARN."
  value       = aws_s3_bucket.checkpoints.arn
}

output "lifecycle_bucket_name" {
  description = "HyperPod lifecycle-script bucket name."
  value       = aws_s3_bucket.lifecycle.bucket
}

output "lifecycle_bucket_arn" {
  description = "HyperPod lifecycle-script bucket ARN."
  value       = aws_s3_bucket.lifecycle.arn
}

output "thanos_bucket_name" {
  description = "Thanos TSDB-blocks bucket name (S3 objstore for the Thanos sidecar/store/compactor)."
  value       = aws_s3_bucket.thanos.bucket
}

output "thanos_bucket_arn" {
  description = "Thanos TSDB-blocks bucket ARN (scopes the Thanos Pod Identity role)."
  value       = aws_s3_bucket.thanos.arn
}

output "loki_bucket_name" {
  description = "Loki chunks/index bucket name (reserved for the Loki logs backend — see follow-up)."
  value       = aws_s3_bucket.loki.bucket
}

output "loki_bucket_arn" {
  description = "Loki bucket ARN (reserved for the Loki logs backend)."
  value       = aws_s3_bucket.loki.arn
}

output "tempo_bucket_name" {
  description = "Tempo traces bucket name (durable trace backend; wire into Tempo storage.trace.s3)."
  value       = aws_s3_bucket.tempo.bucket
}

output "tempo_bucket_arn" {
  description = "Tempo traces bucket ARN."
  value       = aws_s3_bucket.tempo.arn
}

output "fsx_id" {
  description = "FSx for Lustre file system ID."
  value       = aws_fsx_lustre_file_system.this.id
}

output "fsx_mount_name" {
  description = "FSx Lustre mount name (for the CSI PV)."
  value       = aws_fsx_lustre_file_system.this.mount_name
}

output "fsx_dns_name" {
  description = "FSx Lustre DNS name."
  value       = aws_fsx_lustre_file_system.this.dns_name
}
