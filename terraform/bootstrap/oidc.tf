# GitHub OIDC provider and IAM roles for keyless CI/CD authentication

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# If the provider doesn't exist yet, create it:
resource "aws_iam_openid_connect_provider" "github" {
  count = length(data.aws_iam_openid_connect_provider.github.arn) > 0 ? 0 : 1

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_oidc_arn = length(data.aws_iam_openid_connect_provider.github.arn) > 0 ? (
    data.aws_iam_openid_connect_provider.github.arn
  ) : aws_iam_openid_connect_provider.github[0].arn

  github_sub_prefix = "repo:${var.github_org}/${var.github_repo}"
}

# ── Plan Role (any branch, PRs) ───────────────────────────────────────────────
resource "aws_iam_role" "terraform_plan" {
  name        = "cap-plan"
  description = "GitHub Actions OIDC role for Terraform plan — all branches"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "terraform_plan_state" {
  name = "cap-plan-state-access"
  role = aws_iam_role.terraform_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["${aws_s3_bucket.state.arn}", "${aws_s3_bucket.state.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.state_lock.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.state.arn
      }
    ]
  })
}

# ── Apply Role (main branch only) ────────────────────────────────────────────
resource "aws_iam_role" "terraform_apply" {
  name        = "cap-apply"
  description = "GitHub Actions OIDC role for Terraform apply — main branch only"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:ref:refs/heads/main"
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_admin" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── Image Push Role ────────────────────────────────────────────────────────────
resource "aws_iam_role" "image_push" {
  name        = "cap-image-push"
  description = "GitHub Actions OIDC role for ECR image push — main branch only"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:ref:refs/heads/main"
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "image_push_ecr" {
  name = "cap-image-push-ecr"
  role = aws_iam_role.image_push.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
      Resource = "*"
    }]
  })
}

# ── Prowler Role (compliance scanning) ────────────────────────────────────────
resource "aws_iam_role" "prowler" {
  name        = "cap-prowler"
  description = "GitHub Actions OIDC role for Prowler compliance scanning"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prowler_security_audit" {
  role       = aws_iam_role.prowler.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "prowler_readonly" {
  role       = aws_iam_role.prowler.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}
