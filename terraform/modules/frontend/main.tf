data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.name}-frontend-${data.aws_caller_identity.current.account_id}"
  has_domain  = var.domain_name != ""
}

resource "aws_s3_bucket" "spa" {
  bucket = local.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket                  = aws_s3_bucket.spa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.spa.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.spa.arn }
      }
    }]
  })
}

# --- ACM cert (DNS-validated) — only for a custom domain -------------------
resource "aws_acm_certificate" "spa" {
  count = local.has_domain ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "spa_cert_validation" {
  for_each = local.has_domain ? {
    for dvo in aws_acm_certificate.spa[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "spa" {
  count = local.has_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.spa[0].arn
  validation_record_fqdns = [for r in aws_route53_record.spa_cert_validation : r.fqdn]
}

# --- CloudFront -------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "${var.name}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = local.has_domain ? [var.domain_name] : []
  price_class         = var.price_class
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.spa[0].arn : null
  comment             = "${var.name} inference SPA"

  origin {
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id                = "spa-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  default_cache_behavior {
    target_origin_id       = "spa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # SPA client-side routing: serve index.html for unknown paths.
  dynamic "custom_error_response" {
    for_each = toset([403, 404])
    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/index.html"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Custom domain ⇒ ACM cert; otherwise the default *.cloudfront.net cert.
    cloudfront_default_certificate = local.has_domain ? null : true
    acm_certificate_arn            = one(aws_acm_certificate_validation.spa[*].certificate_arn)
    ssl_support_method             = local.has_domain ? "sni-only" : null
    minimum_protocol_version       = local.has_domain ? "TLSv1.2_2021" : null
  }

  tags = var.tags
}

resource "aws_route53_record" "spa" {
  count = local.has_domain ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.spa.domain_name
    zone_id                = aws_cloudfront_distribution.spa.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- WAFv2 (optional) -------------------------------------------------------
resource "aws_wafv2_web_acl" "spa" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.name}-frontend-waf"
  scope       = "CLOUDFRONT"
  description = "${var.name} SPA — managed common rules + rate limit"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-frontend-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-frontend-ratelimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-frontend-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}
