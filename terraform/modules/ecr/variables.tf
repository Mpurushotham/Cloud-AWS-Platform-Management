variable "project" { description = "Project name"; type = string }
variable "environment" { description = "Environment name"; type = string }
variable "repository_names" { description = "List of ECR repository names to create"; type = list(string) }
variable "allowed_account_ids" { description = "Account IDs allowed to pull images cross-account"; type = list(string); default = [] }
variable "kms_key_arn" { description = "KMS key ARN for ECR encryption"; type = string; default = null }
