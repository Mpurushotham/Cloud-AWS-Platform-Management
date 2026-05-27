output "org_id" {
  description = "AWS Organization ID"
  value       = aws_organizations_organization.main.id
}

output "root_id" {
  description = "Organization root ID"
  value       = aws_organizations_organization.main.roots[0].id
}

output "account_ids" {
  description = "Map of account name to account ID"
  value       = { for k, v in aws_organizations_account.accounts : k => v.id }
}

output "ou_ids" {
  description = "Map of OU name to OU ID"
  value = {
    core           = aws_organizations_organizational_unit.core.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    workloads      = aws_organizations_organizational_unit.workloads.id
    non_prod       = aws_organizations_organizational_unit.non_prod.id
    prod           = aws_organizations_organizational_unit.prod.id
    sandbox        = aws_organizations_organizational_unit.sandbox.id
  }
}

output "scp_policy_ids" {
  description = "Map of SCP name to policy ID"
  value       = { for k, v in aws_organizations_policy.scps : k => v.id }
}
