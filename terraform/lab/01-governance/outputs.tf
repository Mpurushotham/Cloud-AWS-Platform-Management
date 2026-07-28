output "organization_id" {
  description = "AWS Organization identifier"
  value       = aws_organizations_organization.this.id
}

output "root_id" {
  description = "Organization root identifier — parent of the top-level OUs"
  value       = local.root_id
}

output "organizational_unit_ids" {
  description = "OU identifiers, keyed by name"
  value = {
    core           = aws_organizations_organizational_unit.core.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    workloads      = aws_organizations_organizational_unit.workloads.id
    non_prod       = aws_organizations_organizational_unit.non_prod.id
    prod           = aws_organizations_organizational_unit.prod.id
    sandbox        = aws_organizations_organizational_unit.sandbox.id
  }
}

output "scp_ids" {
  description = "Service Control Policy identifiers, keyed by policy name"
  value       = { for k, v in aws_organizations_policy.scp : k => v.id }
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket holding organization CloudTrail logs"
  value       = var.enable_organization_trail ? aws_s3_bucket.trail[0].id : null
}

output "cloudtrail_arn" {
  description = "ARN of the organization trail"
  value       = var.enable_organization_trail ? aws_cloudtrail.org[0].arn : null
}

output "access_logs_bucket_name" {
  description = "Central S3 server access log bucket. Consumed by later layers as access_log_bucket_name."
  value       = aws_s3_bucket.access_logs.id
}

output "budget_name" {
  description = "Name of the lab cost guardrail budget"
  value       = aws_budgets_budget.lab_monthly.name
}
