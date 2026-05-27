locals {
  services = ["s3", "rds", "eks", "ecr", "cloudtrail", "ssm", "sns", "cloudwatch", "guardduty", "config", "ecs"]

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
    Owner       = var.owner
  }
}

resource "aws_kms_key" "services" {
  for_each = toset(local.services)

  description             = "KMS key for ${var.project}-${var.environment} ${each.value}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true
  multi_region            = var.environment == "prod" ? true : false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*" } }
      }
    ]
  })

  tags = merge(local.common_tags, { Service = each.value })
}

resource "aws_kms_alias" "services" {
  for_each = toset(local.services)

  name          = "alias/${var.project}/${var.environment}/kms/${each.value}"
  target_key_id = aws_kms_key.services[each.value].key_id
}

data "aws_caller_identity" "current" {}
