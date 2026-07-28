# Organization CloudTrail.
#
# One trail recording management events across all regions is free of charge.
# Data events (S3 object-level, Lambda invoke) are deliberately NOT enabled —
# they are billed per event and would break the lab's zero-cost budget.

resource "aws_s3_bucket" "trail" {
  count  = var.enable_organization_trail ? 1 : 0
  bucket = local.trail_bucket_name
}

resource "aws_s3_bucket_versioning" "trail" {
  count  = var.enable_organization_trail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count  = var.enable_organization_trail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  # SSE-S3 rather than SSE-KMS: a customer-managed key costs $1/month, and
  # CloudTrail's own KMS calls are billed per request. See ADR-0015.
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count                   = var.enable_organization_trail ? 1 : 0
  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count  = var.enable_organization_trail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.trail_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  count = var.enable_organization_trail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.aws_region}:${local.account_id}:trail/cap-lab-org-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    # Organization trails write under /AWSLogs/<org-id>/ as well as
    # /AWSLogs/<account-id>/, so both prefixes must be permitted.
    resources = [
      "${aws_s3_bucket.trail[0].arn}/AWSLogs/${local.account_id}/*",
      "${aws_s3_bucket.trail[0].arn}/AWSLogs/${aws_organizations_organization.this.id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.aws_region}:${local.account_id}:trail/cap-lab-org-trail"]
    }
  }

  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.trail[0].arn,
      "${aws_s3_bucket.trail[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count  = var.enable_organization_trail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket[0].json
}

resource "aws_cloudtrail" "org" {
  count = var.enable_organization_trail ? 1 : 0

  name           = "cap-lab-org-trail"
  s3_bucket_name = aws_s3_bucket.trail[0].id

  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail]
}
