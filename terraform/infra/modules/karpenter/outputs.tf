output "interruption_queue_name" {
  description = "SQS interruption queue name (set as Karpenter settings.interruptionQueue)."
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_arn" {
  description = "SQS interruption queue ARN (referenced by the Karpenter controller IAM policy)."
  value       = aws_sqs_queue.interruption.arn
}
