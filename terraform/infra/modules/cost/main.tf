# ---------------------------------------------------------------------------
# SNS topic for budget + anomaly alerts.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-cost-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Monthly budget with alerts at 50 / 80 / 100% (actual) and 100% (forecast).
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_tag}"]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
      subscriber_email_addresses = var.alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
    subscriber_email_addresses = var.alert_emails
  }
}

# ---------------------------------------------------------------------------
# Cost anomaly detection scoped to this project's tag.
# ---------------------------------------------------------------------------
# Anomaly detection requires at least one subscriber, so it's only created when
# alert emails are provided (no emails => no anomaly monitor/subscription).
resource "aws_ce_anomaly_monitor" "this" {
  count        = length(var.alert_emails) > 0 ? 1 : 0
  name         = "${var.name}-anomaly"
  monitor_type = "CUSTOM"
  monitor_specification = jsonencode({
    Tags = {
      Key          = "Project"
      Values       = [var.project_tag]
      MatchOptions = ["EQUALS"]
    }
  })
}

resource "aws_ce_anomaly_subscription" "this" {
  count            = length(var.alert_emails) > 0 ? 1 : 0
  name             = "${var.name}-anomaly-sub"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(max(var.monthly_budget_usd * 0.1, 10))]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  dynamic "subscriber" {
    for_each = toset(var.alert_emails)
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }
}

# ---------------------------------------------------------------------------
# Auto-stop guard: EventBridge-scheduled Lambda that scales the GPU instance
# group to 0 when average GPU utilization has been ~idle. The strongest cost
# control in the whole stack.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  count = var.auto_stop_idle_minutes > 0 ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auto_stop" {
  count              = var.auto_stop_idle_minutes > 0 ? 1 : 0
  name               = "${var.name}-auto-stop"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "auto_stop" {
  count = var.auto_stop_idle_minutes > 0 ? 1 : 0

  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid    = "HyperPodScale"
    effect = "Allow"
    actions = [
      "sagemaker:DescribeCluster",
      "sagemaker:UpdateCluster",
      "sagemaker:ListClusterNodes",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "auto_stop" {
  count  = var.auto_stop_idle_minutes > 0 ? 1 : 0
  name   = "${var.name}-auto-stop"
  role   = aws_iam_role.auto_stop[0].id
  policy = data.aws_iam_policy_document.auto_stop[0].json
}

data "archive_file" "auto_stop" {
  count       = var.auto_stop_idle_minutes > 0 ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/auto_stop.py"
  output_path = "${path.module}/lambda/auto_stop.zip"
}

# ---------------------------------------------------------------------------
# boto3 layer: the python3.12 runtime ships an older boto3; pin a newer one so
# HyperPod describe_cluster/update_cluster params resolve. Built at apply time by
# pip-installing requirements.txt into layer/python/ (Lambda's import path).
# Requires `pip3` on the machine running `terraform apply`.
# ---------------------------------------------------------------------------
resource "null_resource" "boto3_layer_build" {
  count = var.auto_stop_idle_minutes > 0 ? 1 : 0

  triggers = {
    requirements = filemd5("${path.module}/lambda/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf "${path.module}/lambda/layer"
      pip3 install -r "${path.module}/lambda/requirements.txt" \
        -t "${path.module}/lambda/layer/python" --quiet
    EOT
  }
}

data "archive_file" "boto3_layer" {
  count       = var.auto_stop_idle_minutes > 0 ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda/layer"
  output_path = "${path.module}/lambda/boto3_layer.zip"
  depends_on  = [null_resource.boto3_layer_build]
}

resource "aws_lambda_layer_version" "boto3" {
  count               = var.auto_stop_idle_minutes > 0 ? 1 : 0
  layer_name          = "${var.name}-boto3"
  filename            = data.archive_file.boto3_layer[0].output_path
  source_code_hash    = data.archive_file.boto3_layer[0].output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_lambda_function" "auto_stop" {
  count            = var.auto_stop_idle_minutes > 0 ? 1 : 0
  function_name    = "${var.name}-auto-stop"
  role             = aws_iam_role.auto_stop[0].arn
  runtime          = "python3.12"
  handler          = "auto_stop.handler"
  filename         = data.archive_file.auto_stop[0].output_path
  source_code_hash = data.archive_file.auto_stop[0].output_base64sha256
  layers           = [aws_lambda_layer_version.boto3[0].arn]
  timeout          = 60

  environment {
    variables = {
      CLUSTER_NAME       = var.hyperpod_cluster_name
      GPU_INSTANCE_GROUP = var.gpu_instance_group
      IDLE_MINUTES       = tostring(var.auto_stop_idle_minutes)
      SNS_TOPIC_ARN      = aws_sns_topic.alerts.arn
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "auto_stop" {
  count               = var.auto_stop_idle_minutes > 0 ? 1 : 0
  name                = "${var.name}-auto-stop"
  description         = "Periodically check GPU idleness and scale HyperPod to 0."
  schedule_expression = "rate(${var.auto_stop_idle_minutes} minutes)"
}

resource "aws_cloudwatch_event_target" "auto_stop" {
  count     = var.auto_stop_idle_minutes > 0 ? 1 : 0
  rule      = aws_cloudwatch_event_rule.auto_stop[0].name
  target_id = "auto-stop-lambda"
  arn       = aws_lambda_function.auto_stop[0].arn
}

resource "aws_lambda_permission" "auto_stop" {
  count         = var.auto_stop_idle_minutes > 0 ? 1 : 0
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_stop[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_stop[0].arn
}
