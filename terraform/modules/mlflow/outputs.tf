output "tracking_server_arn" {
  description = "MLflow tracking server ARN. Use as MLFLOW_TRACKING_URI / --mlflow-tracking-uri."
  value       = aws_sagemaker_mlflow_tracking_server.this.arn
}

output "tracking_server_name" {
  description = "MLflow tracking server name."
  value       = aws_sagemaker_mlflow_tracking_server.this.tracking_server_name
}

output "artifact_bucket_name" {
  description = "S3 bucket backing the MLflow artifact store."
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the MLflow artifact store bucket."
  value       = aws_s3_bucket.artifacts.arn
}
