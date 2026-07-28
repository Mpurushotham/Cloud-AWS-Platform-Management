output "platform_admin_role_arn" {
  description = "ARN of cap-platform-admin. Configure this as role_arn in ~/.aws/config."
  value       = aws_iam_role.platform_admin.arn
}

output "account_id" {
  description = "AWS account the lab is deployed into"
  value       = local.account_id
}

output "applied_by_root" {
  description = <<-EOT
    True when this layer was applied using account-root credentials. Expected to be
    true on the very first apply and false on every apply thereafter. If it is still
    true later, the root key retirement in README.md was never completed.
  EOT
  value       = local.applied_by_root
}

output "console_signin_url" {
  description = "Console sign-in URL using the account alias, if one is set."
  value = var.account_alias == null ? (
    "https://${local.account_id}.signin.aws.amazon.com/console"
  ) : "https://${var.account_alias}.signin.aws.amazon.com/console"
}

output "set_organization_account_name" {
  description = <<-EOT
    Command to rename the account in the Organizations console and on the
    billing statement. No Terraform resource covers this, so it is applied out
    of band. Free, and reversible.
  EOT
  value       = <<-EOT
    aws organizations describe-account --account-id ${local.account_id} \
      --query 'Account.Name' --output text        # current name

    aws account put-account-name --account-name "${coalesce(var.account_alias, "cap-platform")}"

    aws organizations describe-account --account-id ${local.account_id} \
      --query 'Account.Name' --output text        # confirm
  EOT
}

output "aws_config_profile_snippet" {
  description = "Paste into ~/.aws/config to start using the role instead of root keys."
  value       = <<-EOT
    [profile cap-lab]
    role_arn       = ${aws_iam_role.platform_admin.arn}
    source_profile = cap-iam-user
    mfa_serial     = arn:${local.partition}:iam::${local.account_id}:mfa/<your-mfa-device-name>
    region         = ${var.aws_region}
  EOT
}
