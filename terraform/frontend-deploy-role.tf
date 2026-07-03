locals {
  frontend_deploy_enabled = var.enable_frontend && var.github_oidc_provider_arn != ""
  frontend_deploy_subject = "repo:${var.github_owner}/${var.github_repo}:environment:production"

  tf_state_key = "kinetics-pipeline-bucket/terraform.tfstate"
}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "frontend_deploy_assume" {
  count = local.frontend_deploy_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.frontend_deploy_subject]
    }
  }
}

resource "aws_iam_role" "frontend_deploy" {
  count = local.frontend_deploy_enabled ? 1 : 0

  name               = "${local.name}-gha-frontend-deploy"
  assume_role_policy = data.aws_iam_policy_document.frontend_deploy_assume[0].json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "frontend_deploy" {
  count = local.frontend_deploy_enabled ? 1 : 0

  statement {
    sid       = "SpaBucketSync"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetObject"]
    resources = [module.frontend[0].spa_bucket_arn, "${module.frontend[0].spa_bucket_arn}/*"]
  }

  statement {
    sid       = "CloudFrontInvalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [module.frontend[0].cloudfront_distribution_arn]
  }

  # Read this stack's outputs (spa_bucket, cloudfront_distribution_id, cognito_*)
  # from the state object at deploy time.
  statement {
    sid       = "ReadTerraformState"
    actions   = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket}/${local.tf_state_key}"]
  }
}

resource "aws_iam_role_policy" "frontend_deploy" {
  count = local.frontend_deploy_enabled ? 1 : 0

  name   = "${local.name}-gha-frontend-deploy"
  role   = aws_iam_role.frontend_deploy[0].id
  policy = data.aws_iam_policy_document.frontend_deploy[0].json
}
