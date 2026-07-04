# ---------------------------------------------------------------------------
# SQS interruption queue. Karpenter watches this to gracefully drain nodes on
# Spot interruption / rebalance / scheduled maintenance — essential when the
# NodePool runs Spot (which it does, for cost). 5-minute retention is plenty;
# these are real-time signals.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

# Allow EventBridge (and the SQS service) to deliver events to the queue,
# scoped to this account.
data "aws_iam_policy_document" "queue_policy" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_cloudwatch_event_rule.spot_interruption.arn,
        aws_cloudwatch_event_rule.rebalance.arn,
        aws_cloudwatch_event_rule.instance_state.arn,
        aws_cloudwatch_event_rule.scheduled_change.arn,
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.queue_policy.json
}

# ---------------------------------------------------------------------------
# EventBridge rules -> SQS. The four event sources Karpenter consumes.
# ---------------------------------------------------------------------------
locals {
  event_rules = {
    spot_interruption = {
      description   = "EC2 Spot interruption warning"
      event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Spot Instance Interruption Warning"] })
    }
    rebalance = {
      description   = "EC2 instance rebalance recommendation"
      event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance Rebalance Recommendation"] })
    }
    instance_state = {
      description   = "EC2 instance state-change"
      event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance State-change Notification"] })
    }
    scheduled_change = {
      description   = "AWS Health scheduled change"
      event_pattern = jsonencode({ source = ["aws.health"], "detail-type" = ["AWS Health Event"] })
    }
  }
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name          = "${var.name}-karpenter-spot-interruption"
  description   = local.event_rules.spot_interruption.description
  event_pattern = local.event_rules.spot_interruption.event_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name          = "${var.name}-karpenter-rebalance"
  description   = local.event_rules.rebalance.description
  event_pattern = local.event_rules.rebalance.event_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_state" {
  name          = "${var.name}-karpenter-instance-state"
  description   = local.event_rules.instance_state.description
  event_pattern = local.event_rules.instance_state.event_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name          = "${var.name}-karpenter-scheduled-change"
  description   = local.event_rules.scheduled_change.description
  event_pattern = local.event_rules.scheduled_change.event_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule = aws_cloudwatch_event_rule.rebalance.name
  arn  = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_target" "instance_state" {
  rule = aws_cloudwatch_event_rule.instance_state.name
  arn  = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule = aws_cloudwatch_event_rule.scheduled_change.name
  arn  = aws_sqs_queue.interruption.arn
}
