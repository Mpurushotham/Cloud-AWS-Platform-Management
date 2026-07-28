# Lab layer 01 — governance.
#
# Resource files:
#   organization.tf          — the AWS Organization itself (imported, not created)
#   organizational-units.tf  — Core / Infrastructure / Workloads / Sandbox tree
#   service-control-policies.tf — SCP definitions and attachments
#   cloudtrail.tf            — organization trail and its log bucket
#   budgets.tf               — cost guardrail
#
# The organization already existed before this repository was written. It is
# imported rather than created; see README.md for the import command.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  trail_bucket_name = coalesce(var.trail_bucket_name, "cap-lab-cloudtrail-${local.account_id}")

  # Service Control Policies are authored once under security/scps/ and consumed
  # here, so the committed policy documents remain the single source of truth.
  scp_dir = "${path.module}/../../../security/scps"

  scps = {
    deny-root-user          = "Block all API activity performed by an account root user"
    deny-delete-cloudtrail  = "Prevent tampering with the audit trail"
    deny-public-s3          = "Prevent buckets and objects from being made public"
    deny-disable-guardduty  = "Prevent threat detection from being switched off"
    require-encryption      = "Require encryption at rest for S3, EBS and RDS"
    deny-region-restriction = "Confine workloads to approved regions"
    require-mfa             = "Require MFA for all non-automation API calls"
  }

  # Attachment plan, matching docs/architecture/overview.md. Policies attached to
  # the root apply to every OU beneath it.
  #
  # AWS caps SCPs at 5 per target and the AWS-managed FullAWSAccess policy
  # occupies one slot, so the four root attachments below sit exactly at quota.
  # Adding a fifth root policy requires merging statements into an existing one.
  scp_attachments = {
    deny-root-user          = local.root_id
    deny-delete-cloudtrail  = local.root_id
    deny-public-s3          = local.root_id
    deny-disable-guardduty  = local.root_id
    require-encryption      = aws_organizations_organizational_unit.workloads.id
    deny-region-restriction = aws_organizations_organizational_unit.workloads.id
    require-mfa             = aws_organizations_organizational_unit.prod.id
  }
}
