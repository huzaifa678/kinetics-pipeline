output "asg_name" {
  description = "Runner Auto Scaling Group name."
  value       = aws_autoscaling_group.runner.name
}

output "runner_labels" {
  description = "Labels the runner advertises (use in workflow runs-on)."
  value       = var.runner_labels
}

output "pat_secret_arn" {
  description = "Secrets Manager secret holding the GitHub runner-registration PAT. Set its value out-of-band: aws secretsmanager put-secret-value."
  value       = aws_secretsmanager_secret.runner_pat.arn
}

output "security_group_id" {
  description = "Runner security group ID."
  value       = aws_security_group.runner.id
}
