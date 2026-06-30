output "spa_bucket" {
  description = "S3 bucket holding the SPA build artifacts (CI syncs dist/ here)."
  value       = aws_s3_bucket.spa.bucket
}

output "spa_bucket_arn" {
  description = "S3 bucket ARN (for the CI deploy role's put policy)."
  value       = aws_s3_bucket.spa.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation in CI)."
  value       = aws_cloudfront_distribution.spa.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN (for the CI deploy role's invalidation policy)."
  value       = aws_cloudfront_distribution.spa.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain (the Route53 alias target)."
  value       = aws_cloudfront_distribution.spa.domain_name
}

output "spa_url" {
  description = "Public SPA URL (custom domain if set, else the default CloudFront URL)."
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.spa.domain_name}"
}
