output "amp_workspace_id" {
  description = "AMP workspace ID (null when disabled)."
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].id : null
}

output "amp_workspace_arn" {
  description = "AMP workspace ARN — scopes the remote_write IAM role (empty when disabled)."
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].arn : ""
}

output "amp_remote_write_url" {
  description = "AMP remote_write endpoint — set as prometheus.prometheusSpec.remoteWrite[].url in the GitOps kube-prometheus-stack values (null when disabled)."
  value       = var.enable_managed_prometheus ? "${aws_prometheus_workspace.this[0].prometheus_endpoint}api/v1/remote_write" : null
}

output "amp_query_url" {
  description = "AMP query endpoint (Prometheus-compatible base URL; null when disabled)."
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].prometheus_endpoint : null
}

output "grafana_workspace_endpoint" {
  description = "AMG workspace endpoint URL (null when disabled)."
  value       = var.enable_managed_grafana ? aws_grafana_workspace.this[0].endpoint : null
}

output "grafana_workspace_id" {
  description = "AMG workspace ID (null when disabled)."
  value       = var.enable_managed_grafana ? aws_grafana_workspace.this[0].id : null
}
