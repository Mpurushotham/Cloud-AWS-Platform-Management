variable "member_account_emails" { description = "Map of account_id→email for GuardDuty member enrollment"; type = map(string); default = {} }
variable "finding_s3_bucket_arn" { description = "S3 bucket ARN for GuardDuty finding export"; type = string }
variable "kms_key_arn" { description = "KMS key ARN for GuardDuty findings encryption"; type = string }
variable "environment" { description = "Environment name"; type = string; default = "security" }
