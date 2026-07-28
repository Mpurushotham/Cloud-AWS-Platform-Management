# Terraform remote state: versioned S3 bucket plus a DynamoDB lock table.

resource "aws_kms_key" "state" {
  count = local.use_kms ? 1 : 0

  description             = "Encrypts the cap lab Terraform state bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.state_key[0].json
}

resource "aws_kms_alias" "state" {
  count = local.use_kms ? 1 : 0

  name          = "alias/cap/lab/kms/tfstate"
  target_key_id = aws_kms_key.state[0].key_id
}

data "aws_iam_policy_document" "state_key" {
  count = local.use_kms ? 1 : 0

  # Account principals administer the key through IAM. This is the AWS-required
  # escape hatch that prevents a key from becoming permanently unmanageable.
  statement {
    sid    = "EnableIAMPolicies"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # The CI roles get data-plane use only — never key administration.
  statement {
    sid    = "AllowCIRolesDataPlaneUse"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.terraform_plan.arn,
        aws_iam_role.terraform_apply.arn,
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # State loss is unrecoverable without a backup; refuse to destroy it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  # Versioning is what makes state corruption recoverable — roll back to the
  # previous object version rather than rebuilding from the live infrastructure.
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.state_encryption
      kms_master_key_id = local.use_kms ? aws_kms_key.state[0].arn : null
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

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = var.access_log_bucket_name
  target_prefix = "s3-access/${local.state_bucket_name}/"
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    # Keep enough history to recover from a bad apply without unbounded growth.
    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyUnencryptedWrites"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [var.state_encryption]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

# State locking. Terraform 1.10 can lock natively in S3 via use_lockfile, which
# removes this table; this repository pins ~> 1.9, so the table is still needed.
# nosemgrep: aws-dynamodb-table-unencrypted -- key choice follows
# var.state_encryption; defaults to an AWS-owned key for cost. See ADR-0015.
resource "aws_dynamodb_table" "state_lock" {
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = local.use_kms
    kms_key_arn = local.use_kms ? aws_kms_key.state[0].arn : null
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
