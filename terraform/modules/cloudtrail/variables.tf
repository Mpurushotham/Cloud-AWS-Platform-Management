variable "project" { description = "Project name"; type = string }
variable "environment" { description = "Environment"; type = string }
variable "kms_key_arn" { description = "KMS key ARN for CloudTrail encryption"; type = string }
variable "s3_bucket_id" { description = "S3 bucket ID for CloudTrail log delivery"; type = string }
variable "s3_bucket_arn" { description = "S3 bucket ARN"; type = string }
variable "log_retention_days" { description = "CloudWatch log retention in days"; type = number; default = 365 }
