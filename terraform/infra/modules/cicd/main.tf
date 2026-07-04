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
  #   * apply: the default branch (push) OR any of the per-env GitHub Environments
  #            (dispatch sets environment:<profile>; gate each in repo Settings).
  #   * plan:  pull-request runs, plus the default branch (manual plan dispatch).
  main_subjects = concat(
    ["repo:${local.repo}:ref:refs/heads/${var.default_branch}"],
    [for e in distinct(concat([var.apply_environment], var.apply_environments)) :
    "repo:${local.repo}:environment:${e}"],
  )
  pr_subjects = [
    "repo:${local.repo}:pull_request",
    "repo:${local.repo}:ref:refs/heads/${var.default_branch}",
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

# AWS ReadOnlyAccess deliberately omits sensitive reads that `terraform plan`
# needs while refreshing state — e.g. the MSK SCRAM secret (GetSecretValue) and
# its customer-managed KMS key (Decrypt). Read-only; the plan role still can't
# write anything.
data "aws_iam_policy_document" "tf_plan_reads" {
  statement {
    sid       = "SensitiveReadsForRefresh"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "kms:Decrypt"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tf_plan_reads" {
  name   = "${var.name}-gha-tf-plan-reads"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan_reads.json
}


resource "aws_iam_role" "tf_apply" {
  name               = "${var.name}-gha-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.assume_main.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${var.apply_managed_policy}"
}

# ===========================================================================
# Role 4: frontend deploy (frontend-deploy.yml). Syncs the SPA build to S3 and
# invalidates CloudFront. Created only when the frontend bucket ARN is passed
# (i.e. enable_frontend). Trusted on the same subjects as apply.
# ===========================================================================
resource "aws_iam_role" "frontend_deploy" {
  count = var.frontend_bucket_arn != "" ? 1 : 0

  name               = "${var.name}-gha-frontend-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "frontend_deploy" {
  count = var.frontend_bucket_arn != "" ? 1 : 0

  statement {
    sid       = "SpaBucketSync"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetObject"]
    resources = [var.frontend_bucket_arn, "${var.frontend_bucket_arn}/*"]
  }

  statement {
    sid       = "CloudFrontInvalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = var.frontend_distribution_arn != "" ? [var.frontend_distribution_arn] : ["*"]
  }
}

resource "aws_iam_role_policy" "frontend_deploy" {
  count = var.frontend_bucket_arn != "" ? 1 : 0

  name   = "${var.name}-gha-frontend-deploy"
  role   = aws_iam_role.frontend_deploy[0].id
  policy = data.aws_iam_policy_document.frontend_deploy[0].json
}

data "aws_partition" "current" {}
