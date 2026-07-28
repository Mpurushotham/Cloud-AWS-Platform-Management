# Standing privilege for the human IAM user.
#
# The intended shape is that the user holds almost nothing: enough to manage its
# own credentials and MFA device, and enough to assume cap-platform-admin. All
# real authority comes from assuming that role, which requires MFA.
#
# This matters because permissions attached directly to a user apply to every
# session, MFA or not. A user carrying AdministratorAccess is barely better than
# root: an attacker with only the access key gets full admin without ever
# presenting a second factor.
#
# ORDERING WARNING. Attaching this policy is additive and safe. *Removing* the
# broad policies currently on the user's group is not, and must happen only
# after MFA is enrolled and role assumption is proven to work. Doing it first
# locks the user out of everything except root. See README.md.

resource "aws_iam_policy" "assume_platform_admin" {
  count = var.human_user_name == null ? 0 : 1

  name        = "cap-assume-platform-admin"
  description = "Assume cap-platform-admin, and self-manage credentials and MFA."
  policy      = data.aws_iam_policy_document.assume_platform_admin[0].json
}

data "aws_iam_policy_document" "assume_platform_admin" {
  count = var.human_user_name == null ? 0 : 1

  statement {
    sid       = "AssumePlatformAdmin"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.platform_admin.arn]
  }

  # Self-service credential management. Without this the user cannot enrol an
  # MFA device, and cannot therefore ever satisfy the role's trust condition.
  statement {
    sid    = "ManageOwnCredentials"
    effect = "Allow"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:user/$${aws:username}"]
  }

  statement {
    sid    = "ManageOwnMFA"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:ListMFADevices",
      "iam:DeactivateMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:mfa/$${aws:username}",
      "arn:${local.partition}:iam::${local.account_id}:user/$${aws:username}",
    ]
  }

  # Needed for the console and CLI to show the user what exists.
  statement {
    sid    = "ReadOwnIdentity"
    effect = "Allow"
    actions = [
      "iam:ListVirtualMFADevices",
      "iam:ListAccountAliases",
      "iam:GetAccountPasswordPolicy",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy_attachment" "assume_platform_admin" {
  count = var.human_user_name == null ? 0 : 1

  user       = var.human_user_name
  policy_arn = aws_iam_policy.assume_platform_admin[0].arn
}
