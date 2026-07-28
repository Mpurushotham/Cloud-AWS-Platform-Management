# Account naming.
#
# Two distinct names, often confused:
#
#   IAM account alias  — replaces the 12-digit account ID in the console sign-in
#                        URL. One per account, globally unique across all of AWS.
#                        https://<alias>.signin.aws.amazon.com/console
#
#   Organizations name — the label shown in the Organizations console and on the
#                        billing statement. Not globally unique, no sign-in role.
#
# Neither has anything to do with Route 53, despite both being "names". Route 53
# registers DNS domains, which is a separate, billable thing: a hosted zone is
# $0.50/month and a domain registration is $12+/year. Nothing here costs money.

resource "aws_iam_account_alias" "this" {
  count = var.account_alias == null ? 0 : 1

  account_alias = var.account_alias
}

# The Organizations account name is changed through the Account API rather than
# a Terraform resource — no provider resource covers it. See the note in
# outputs.tf for the command.
