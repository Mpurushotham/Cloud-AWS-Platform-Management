# Bootstrap layer — run once manually as org admin.
# Creates: S3 state bucket, DynamoDB lock table, GitHub OIDC IdP, four IAM roles.
# After first apply, run: terraform init -migrate-state

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── S3 State Bucket ───────────────────────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["${aws_s3_bucket.state.arn}", "${aws_s3_bucket.state.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid    = "AllowOIDCRoles"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.terraform_plan.arn,
            aws_iam_role.terraform_apply.arn,
          ]
        }
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = ["${aws_s3_bucket.state.arn}", "${aws_s3_bucket.state.arn}/*"]
      }
    ]
  })
}

# ── KMS Key for State Bucket ──────────────────────────────────────────────────
resource "aws_kms_key" "state" {
  description             = "KMS key for Terraform state bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "state" {
  name          = "alias/cap/bootstrap/kms/state"
  target_key_id = aws_kms_key.state.key_id
}

# ── DynamoDB Lock Table ────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "state_lock" {
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
