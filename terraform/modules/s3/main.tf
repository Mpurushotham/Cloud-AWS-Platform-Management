resource "aws_s3_bucket" "main" {
  bucket = "${var.project}-${var.environment}-${var.bucket_suffix}"
  tags   = local.common_tags
  lifecycle { prevent_destroy = var.prevent_destroy }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = var.versioning_enabled ? "Enabled" : "Suspended" }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "DenyNonTLS", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = ["${aws_s3_bucket.main.arn}", "${aws_s3_bucket.main.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid = "DenyNonEncryptedUploads", Effect = "Deny", Principal = "*", Action = "s3:PutObject", Resource = "${aws_s3_bucket.main.arn}/*", Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } } }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.main.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"
      transition {
        days          = rule.value.transition_days
        storage_class = rule.value.transition_class
      }
      expiration { days = rule.value.expiration_days }
    }
  }
}

locals {
  common_tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform", CostCenter = var.cost_center, Owner = var.owner }
}
