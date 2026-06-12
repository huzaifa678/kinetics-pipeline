data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name}-mlflow-artifacts-${local.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Tracking-server role. Assumed by SageMaker; grants the managed MLflow server
# read/write to the artifact bucket.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tracking_server" {
  name               = "${var.name}-mlflow-server"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "tracking_server" {
  statement {
    sid    = "ArtifactStoreAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "tracking_server" {
  name   = "${var.name}-mlflow-server"
  role   = aws_iam_role.tracking_server.id
  policy = data.aws_iam_policy_document.tracking_server.json
}


resource "aws_sagemaker_mlflow_tracking_server" "this" {
  tracking_server_name = "${var.name}-mlflow"
  artifact_store_uri   = "s3://${aws_s3_bucket.artifacts.bucket}/mlflow"
  role_arn             = aws_iam_role.tracking_server.arn
  tracking_server_size = var.tracking_server_size
  mlflow_version               = var.mlflow_version != "" ? var.mlflow_version : null
  automatic_model_registration = var.automatic_model_registration

  tags = var.tags
}


data "aws_iam_policy_document" "trainer_access" {
  statement {
    sid    = "MlflowAccess"
    effect = "Allow"
    actions = [
      "sagemaker-mlflow:*",
      "sagemaker:DescribeMlflowTrackingServer",
      "sagemaker:CreatePresignedMlflowTrackingServerUrl",
    ]
    resources = [aws_sagemaker_mlflow_tracking_server.this.arn]
  }

  statement {
    sid    = "MlflowArtifactStoreAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "trainer_access" {
  count  = var.trainer_role_name == "" ? 0 : 1
  name   = "${var.name}-mlflow-trainer-access"
  role   = var.trainer_role_name
  policy = data.aws_iam_policy_document.trainer_access.json
}
