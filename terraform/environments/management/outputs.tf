output "org_id" {
  description = "AWS Organization ID"
  value       = module.organizations.org_id
}

output "root_id" {
  description = "Organization root ID"
  value       = module.organizations.root_id
}

output "account_ids" {
  description = "Map of account name to account ID"
  value       = module.organizations.account_ids
}

output "ou_ids" {
  description = "Map of OU name to OU ID"
  value       = module.organizations.ou_ids
}
