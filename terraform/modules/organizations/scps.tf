# Service Control Policies applied at OU and root level

locals {
  scp_policies = {
    deny_root_user = {
      name        = "cap-deny-root-user"
      description = "Deny all API calls made by root principal"
      target_ids  = [aws_organizations_organization.main.roots[0].id]
      content     = file("${path.module}/../scp/policies/deny-root-user.json")
    }
    deny_region = {
      name        = "cap-deny-region-restriction"
      description = "Deny actions in non-approved regions"
      target_ids  = [aws_organizations_organizational_unit.workloads.id]
      content     = templatefile("${path.module}/../scp/policies/deny-region.json.tpl", { allowed_regions = var.allowed_regions })
    }
    require_encryption = {
      name        = "cap-require-encryption"
      description = "Deny unencrypted S3, EBS, RDS resources"
      target_ids  = [aws_organizations_organizational_unit.workloads.id]
      content     = file("${path.module}/../scp/policies/require-encryption.json")
    }
    deny_public_s3 = {
      name        = "cap-deny-public-s3"
      description = "Deny disabling S3 block public access"
      target_ids  = [aws_organizations_organization.main.roots[0].id]
      content     = file("${path.module}/../scp/policies/deny-public-s3.json")
    }
    require_mfa = {
      name        = "cap-require-mfa"
      description = "Deny non-STS API calls without MFA"
      target_ids  = [aws_organizations_organizational_unit.prod.id]
      content     = file("${path.module}/../scp/policies/require-mfa.json")
    }
    deny_delete_cloudtrail = {
      name        = "cap-deny-delete-cloudtrail"
      description = "Deny stopping or deleting CloudTrail"
      target_ids  = [aws_organizations_organization.main.roots[0].id]
      content     = file("${path.module}/../scp/policies/deny-delete-cloudtrail.json")
    }
    deny_disable_guardduty = {
      name        = "cap-deny-disable-guardduty"
      description = "Deny disabling GuardDuty"
      target_ids  = [aws_organizations_organization.main.roots[0].id]
      content     = file("${path.module}/../scp/policies/deny-disable-guardduty.json")
    }
  }
}

resource "aws_organizations_policy" "scps" {
  for_each = local.scp_policies

  name        = each.value.name
  description = each.value.description
  content     = each.value.content
  type        = "SERVICE_CONTROL_POLICY"
}

resource "aws_organizations_policy_attachment" "scps" {
  for_each = local.scp_policies

  policy_id = aws_organizations_policy.scps[each.key].id
  target_id = each.value.target_ids[0]
}
