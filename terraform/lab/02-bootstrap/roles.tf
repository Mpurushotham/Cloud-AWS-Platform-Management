# The four GitHub Actions roles. Each federates through the OIDC provider and
# is scoped by the `sub` claim to a specific slice of the repository's activity.
#
# | Role            | Who may assume it            | Consumed by                |
# |-----------------|------------------------------|----------------------------|
# | cap-plan        | any branch or pull request   | 07-terraform-plan.yml      |
# | cap-apply       | the apply branch only        | 08-terraform-apply.yml     |
# | cap-image-push  | the apply branch only        | 04-container-security.yml  |
# | cap-prowler     | any branch                   | 06-compliance.yml          |

# Trust for roles callable from any ref in this repository.
data "aws_iam_policy_document" "trust_any_ref" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # The audience check is what stops a token minted for another relying party
    # being replayed against AWS. It is never optional.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Anchored to this repository. A bare "repo:*" would trust every repository
    # on GitHub.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.sub_any]
    }
  }
}

# Trust for roles callable only from the protected branch.
data "aws_iam_policy_document" "trust_apply_branch" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike: an exact ref match. A pull request from a
    # fork cannot produce this claim.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.sub_apply_branch]
    }
  }
}

# ── cap-plan ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "terraform_plan" {
  name               = "cap-plan"
  description        = "Terraform plan from any branch or pull request. Read-only."
  assume_role_policy = data.aws_iam_policy_document.trust_any_ref.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "cap-plan-state-access"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

data "aws_iam_policy_document" "plan_state" {
  # Read state only. A plan must never mutate the state object.
  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  # A plan does take the lock, so write access to the lock table is required.
  statement {
    sid       = "AcquireStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.state_lock.arn]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "DecryptState"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      resources = [aws_kms_key.state[0].arn]
    }
  }
}

# ── cap-apply ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "terraform_apply" {
  name               = "cap-apply"
  description        = "Terraform apply from the protected branch only."
  assume_role_policy = data.aws_iam_policy_document.trust_apply_branch.json
}

resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# Terraform genuinely needs broad rights, so the containment strategy is a set
# of unconditional denies rather than an enumerated allow-list. Explicit deny
# always wins over the AdministratorAccess allow above.
resource "aws_iam_role_policy" "apply_guardrails" {
  name   = "cap-apply-guardrails"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.apply_guardrails.json
}

data "aws_iam_policy_document" "apply_guardrails" {
  # Long-lived credentials are the thing OIDC exists to remove. CI must not be
  # able to mint them.
  statement {
    sid    = "NoLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateUser",
    ]
    resources = ["*"]
  }

  # CI must not be able to widen its own trust policy or escape its guardrails.
  statement {
    sid    = "NoSelfEscalation"
    effect = "Deny"
    actions = [
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = [
      aws_iam_role.terraform_apply.arn,
      "arn:${local.partition}:iam::${local.account_id}:role/cap-platform-admin",
    ]
  }

  # Named resources rather than a tag condition: S3 does not evaluate
  # aws:ResourceTag on s3:DeleteBucket, so a tag-based deny would silently fail
  # to protect the state bucket — the one thing that most needs protecting.
  statement {
    sid    = "ProtectStateBackend"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "dynamodb:DeleteTable",
    ]
    resources = [
      aws_s3_bucket.state.arn,
      aws_dynamodb_table.state_lock.arn,
    ]
  }

  statement {
    sid    = "ProtectAuditTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "cap-apply-state-access"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.apply_state.json
}

data "aws_iam_policy_document" "apply_state" {
  statement {
    sid       = "ReadWriteState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "HoldStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.state_lock.arn]
  }
}

# ── cap-image-push ────────────────────────────────────────────────────────────
resource "aws_iam_role" "image_push" {
  name               = "cap-image-push"
  description        = "Push container images to ECR from the protected branch only."
  assume_role_policy = data.aws_iam_policy_document.trust_apply_branch.json
}

resource "aws_iam_role_policy" "image_push" {
  name   = "cap-image-push-ecr"
  role   = aws_iam_role.image_push.id
  policy = data.aws_iam_policy_document.image_push.json
}

data "aws_iam_policy_document" "image_push" {
  # GetAuthorizationToken is account-scoped and cannot name a resource.
  statement {
    sid       = "AuthenticateToRegistry"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything else is confined to repositories in this account.
  statement {
    sid    = "PushAndPullImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
    ]
    resources = ["arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository/cap-*"]
  }

  # Image deletion is a supply-chain concern; releases are immutable.
  statement {
    sid       = "NoImageDeletion"
    effect    = "Deny"
    actions   = ["ecr:BatchDeleteImage", "ecr:DeleteRepository"]
    resources = ["*"]
  }
}

# ── cap-prowler ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "prowler" {
  name               = "cap-prowler"
  description        = "Compliance scanning. Read and audit only, never mutating."
  assume_role_policy = data.aws_iam_policy_document.trust_any_ref.json
}

resource "aws_iam_role_policy_attachment" "prowler_security_audit" {
  role       = aws_iam_role.prowler.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "prowler_view_only" {
  role       = aws_iam_role.prowler.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
}

# Prowler needs a handful of read APIs that neither managed policy grants.
resource "aws_iam_role_policy" "prowler_additional" {
  name   = "cap-prowler-additional-reads"
  role   = aws_iam_role.prowler.id
  policy = data.aws_iam_policy_document.prowler_additional.json
}

data "aws_iam_policy_document" "prowler_additional" {
  statement {
    sid    = "AdditionalReadOnly"
    effect = "Allow"
    actions = [
      "account:Get*",
      "account:List*",
      "organizations:Describe*",
      "organizations:List*",
      "support:Describe*",
    ]
    resources = ["*"]
  }
}
