resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names)

  name                 = "${var.project}-${var.environment}-${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

data "aws_caller_identity" "current" {}
