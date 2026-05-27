output "key_ids" {
  description = "Map of service name to KMS key ID"
  value       = { for k, v in aws_kms_key.services : k => v.key_id }
}

output "key_arns" {
  description = "Map of service name to KMS key ARN"
  value       = { for k, v in aws_kms_key.services : k => v.arn }
}

output "alias_arns" {
  description = "Map of service name to KMS alias ARN"
  value       = { for k, v in aws_kms_alias.services : k => v.arn }
}
