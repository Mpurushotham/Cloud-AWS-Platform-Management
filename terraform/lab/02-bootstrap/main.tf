# Lab layer 02 — bootstrap.
#
# Resource files:
#   state-backend.tf — S3 state bucket and DynamoDB lock table
#   oidc.tf          — GitHub OIDC identity provider
#   roles.tf         — the four CI/CD roles that federate through it
#
# Chicken-and-egg: this layer creates the backend that every other layer stores
# its state in, so it necessarily starts on a local backend and migrates to
# itself afterwards. See README.md.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  state_bucket_name = coalesce(var.state_bucket_name, "cap-lab-tfstate-${local.account_id}")

  use_kms = var.state_encryption == "aws:kms"

  # OIDC subject claims. GitHub sets `sub` differently depending on the trigger,
  # so branch-scoped and environment-scoped claims are both spelled out rather
  # than collapsed into a wildcard.
  repo_prefix      = "repo:${var.github_org}/${var.github_repo}"
  sub_any          = "${local.repo_prefix}:*"
  sub_apply_branch = "${local.repo_prefix}:ref:refs/heads/${var.apply_branch}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
