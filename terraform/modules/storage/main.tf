data "aws_caller_identity" "current" {}

locals {
  suffix = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "data" {
  bucket = "${var.name}-data-${local.suffix}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Checkpoint bucket. COST CONTROL: lifecycle transitions old checkpoints to
# Infrequent Access, then expires them, so Spot-interrupt checkpoints don't
# pile up forever.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "checkpoints" {
  bucket = "${var.name}-checkpoints-${local.suffix}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "checkpoints" {
  bucket                  = aws_s3_bucket.checkpoints.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    # Empty filter = apply to all objects in the bucket.
    filter {}

    transition {
      days          = max(var.checkpoint_retention_days - 15, 1)
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.checkpoint_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle-script bucket for HyperPod node bootstrap (on_create scripts).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "lifecycle" {
  bucket = "${var.name}-lifecycle-${local.suffix}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "lifecycle" {
  bucket                  = aws_s3_bucket.lifecycle.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# FSx for Lustre, linked to the dataset bucket. Fast parallel reads for video
# decoding so GPUs aren't starved. COST CONTROL: SCRATCH_2 is cheapest;
# size to working set and destroy when idle (terraform destroy -target).
# ---------------------------------------------------------------------------
resource "aws_fsx_lustre_file_system" "this" {
  storage_capacity            = var.fsx_storage_capacity_gb
  subnet_ids                  = [var.private_subnet_id]
  deployment_type             = "SCRATCH_2"
  per_unit_storage_throughput = null

  # Lazy-load dataset objects from S3 on first access.
  import_path        = "s3://${aws_s3_bucket.data.bucket}"
  auto_import_policy = "NEW_CHANGED"

  tags = merge(var.tags, { Name = "${var.name}-fsx" })
}
