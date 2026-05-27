variable "aws_region" { description = "AWS region"; type = string; default = "us-east-1" }
variable "security_account_id" { description = "Security account ID"; type = string }
variable "cost_center" { description = "Cost center tag"; type = string }
variable "member_account_ids" { description = "All member account IDs"; type = list(string) }
variable "member_account_emails" { description = "Member account ID→email map"; type = map(string) }
variable "logging_s3_bucket_arn" { description = "ARN of centralized logging S3 bucket"; type = string }
variable "security_sns_endpoint" { description = "SNS endpoint for security alerts"; type = string }
variable "sso_instance_arn" { description = "IAM Identity Center instance ARN"; type = string }
variable "sso_identity_store_id" { description = "IAM Identity Center identity store ID"; type = string }
variable "all_account_ids" { description = "Map of account name→ID for SSO assignments"; type = map(string) }
variable "sso_group_ids" { description = "Map of group name→group ID in identity store"; type = map(string) }
