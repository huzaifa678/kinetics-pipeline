output "alerts_topic_arn" {
  description = "SNS topic ARN for cost alerts."
  value       = aws_sns_topic.alerts.arn
}

output "budget_name" {
  description = "Monthly budget name."
  value       = aws_budgets_budget.monthly.name
}

output "auto_stop_function_name" {
  description = "Auto-stop Lambda name (empty if disabled)."
  value       = var.auto_stop_idle_minutes > 0 ? aws_lambda_function.auto_stop[0].function_name : ""
}
