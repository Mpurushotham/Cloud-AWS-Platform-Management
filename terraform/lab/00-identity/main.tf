# Lab layer 00 — identity remediation.
#
# Purpose: retire the account-root access keys that this lab was originally
# bootstrapped with, replacing them with an MFA-gated assumable role.
#
# Resource files:
#   roles.tf      — cap-platform-admin role and its trust policy
#   hardening.tf  — account-wide IAM and S3 baseline controls
#
# Apply this layer FIRST. Every later layer is designed to run as
# cap-platform-admin, not as root. See README.md for the cutover procedure.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Surfaced in outputs so the cutover runbook can assert that the operator
  # applying this layer is the one who will lose root access afterwards.
  applied_by_root = endswith(data.aws_caller_identity.current.arn, ":root")
}
