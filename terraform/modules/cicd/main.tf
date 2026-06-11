terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    tls = { source = "hashicorp/tls" }
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — keyless AWS auth. Workflows present a short-lived OIDC
# token (no long-lived access keys to store/rotate/leak); AWS trusts it via this
# provider and the per-job roles below scope what each workflow may do.
# ---------------------------------------------------------------------------

# Fetch GitHub's OIDC TLS cert so the thumbprint is never hardcoded/stale.
data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [for c in data.tls_certificate.github[0].certificates : c.sha1_fingerprint]
  tags            = var.tags
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn
  repo         = "${var.github_owner}/${var.github_repo}"

  # Which GitHub ref/context each role will accept (the OIDC `sub` claim).
  #   * push/apply: only the default branch or the protected `production` env.
  #   * plan:       only pull-request runs (read-only).
  main_subjects = [
    "repo:${local.repo}:ref:refs/heads/${var.default_branch}",
    "repo:${local.repo}:environment:${var.apply_environment}",
  ]
  pr_subjects = [
    "repo:${local.repo}:pull_request",
  ]
}

# Reusable assume-role trust: Web Identity from the GitHub provider, locked to
# the sts.amazonaws.com audience and the given `sub` subjects.
data "aws_iam_policy_document" "assume_main" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.main_subjects
    }
  }
}

data "aws_iam_policy_document" "assume_pr" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.pr_subjects
    }
  }
}

# ===========================================================================
# Role 1: ECR push (docker-build.yml). Least privilege — only this repo's ECR.
# ===========================================================================
resource "aws_iam_role" "ecr_push" {
  name               = "${var.name}-gha-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.assume_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "EcrPushToRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${var.name}-gha-ecr-push"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ===========================================================================
# Role 2: Terraform plan (terraform-plan.yml). Read-only across the account +
# read/write only on the remote state object/lock. Runs on pull requests.
# ===========================================================================
resource "aws_iam_role" "tf_plan" {
  name               = "${var.name}-gha-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.assume_pr.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_state" {
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}"]
  }
  statement {
    sid    = "StateObjectRW"
    effect = "Allow"
    # GetObject/PutObject/DeleteObject cover read, write and the S3-native
    # lockfile (use_lockfile) the backend uses.
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  name   = "${var.name}-gha-tf-plan-state"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_state.json
}

# ===========================================================================
# Role 3: Terraform apply (terraform-apply.yml). Broad — this stack creates IAM
# roles, KMS keys, EKS, SageMaker, etc. Protected by tight trust (default branch
# or the `production` GitHub Environment, which gates on required reviewers).
# ===========================================================================
resource "aws_iam_role" "tf_apply" {
  name               = "${var.name}-gha-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.assume_main.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${var.apply_managed_policy}"
}

data "aws_partition" "current" {}
