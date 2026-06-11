output "repository_url" {
  description = "ECR repository URL (the image.repository for the training chart)."
  value       = aws_ecr_repository.training.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN (for scoping the CI push role)."
  value       = aws_ecr_repository.training.arn
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.training.name
}
