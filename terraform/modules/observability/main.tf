data "aws_partition" "current" {}

resource "aws_prometheus_workspace" "this" {
  count = var.enable_managed_prometheus ? 1 : 0

  alias = "${var.name}-amp"
  tags  = var.tags
}


data "aws_iam_policy_document" "grafana_assume" {
  count = var.enable_managed_grafana ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  statement {
    sid = "AmpQuery"
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata",
    ]
    resources = ["*"]
  }

  statement {
    sid = "XRayRead"
    actions = [
      "xray:BatchGetTraces",
      "xray:GetServiceGraph",
      "xray:GetTraceGraph",
      "xray:GetTraceSummaries",
      "xray:GetGroups",
      "xray:GetGroup",
      "xray:GetTimeSeriesServiceStatistics",
      "xray:GetInsightSummaries",
      "xray:GetInsight",
      "xray:ListInsightEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  name               = "${var.name}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  name   = "${var.name}-grafana"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana[0].json
}

resource "aws_grafana_workspace" "this" {
  count = var.enable_managed_grafana ? 1 : 0

  name                     = "${var.name}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  data_sources             = ["PROMETHEUS", "XRAY"]
  role_arn                 = aws_iam_role.grafana[0].arn
  tags                     = var.tags
}
