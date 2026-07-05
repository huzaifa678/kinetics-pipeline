resource "aws_ecr_repository" "training" {
  # checkov:skip=CKV_AWS_136:Images are non-secret build artifacts; AES256 at-rest is adequate, KMS adds puller key-policy overhead for no gain.
  name = var.repository_name

  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_ecr_lifecycle_policy" "training" {
  repository = aws_ecr_repository.training.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 3 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 3
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
