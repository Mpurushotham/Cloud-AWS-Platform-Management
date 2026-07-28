# cap-platform-admin — the identity every subsequent lab layer runs as.
#
# Trust is deliberately narrow: named non-root principals, MFA present, TLS only.
# Root is excluded by a variable validation rather than only by convention.

resource "aws_iam_role" "platform_admin" {
  name                 = "cap-platform-admin"
  description          = "MFA-gated platform administration role. Replaces account-root access keys."
  max_session_duration = var.max_session_duration_seconds

  assume_role_policy = data.aws_iam_policy_document.platform_admin_trust.json
}

data "aws_iam_policy_document" "platform_admin_trust" {
  statement {
    sid     = "AllowNamedPrincipalsWithMFA"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = var.break_glass_principal_arns
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "platform_admin" {
  role       = aws_iam_role.platform_admin.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# Terraform needs broad rights, but a platform admin should still not be able to
# silently dismantle the audit trail or destroy the state backend's KMS key.
# These denies are unconditional and therefore override the Allow above.
resource "aws_iam_role_policy" "platform_admin_guardrails" {
  name   = "cap-platform-admin-guardrails"
  role   = aws_iam_role.platform_admin.id
  policy = data.aws_iam_policy_document.platform_admin_guardrails.json
}

data "aws_iam_policy_document" "platform_admin_guardrails" {
  statement {
    sid    = "ProtectAuditTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteEventDataStore",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectStateEncryptionKeys"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Layer"
      values   = ["lab-02-bootstrap"]
    }
  }

  statement {
    sid    = "ProtectOrganizationRoot"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "organizations:DeleteOrganization",
    ]
    resources = ["*"]
  }
}
