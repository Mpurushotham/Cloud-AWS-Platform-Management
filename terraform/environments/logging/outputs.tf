output "audit_bucket_arn" { value = module.s3_audit.bucket_arn }
output "audit_bucket_id" { value = module.s3_audit.bucket_id }
output "cloudtrail_arn" { value = module.cloudtrail.trail_arn }
output "kms_key_arns" { value = module.kms.key_arns }
