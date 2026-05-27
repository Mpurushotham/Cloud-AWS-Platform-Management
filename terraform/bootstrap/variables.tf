variable "aws_region" {
  description = "Primary AWS region for bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "management_account_id" {
  description = "AWS account ID of the management/root account"
  type        = string
}

variable "logging_account_id" {
  description = "AWS account ID for the centralized logging account (state bucket lives here)"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name (used in OIDC trust policy)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (used in OIDC trust policy)"
  type        = string
  default     = "Cloud-AWS-Platform-Management"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state"
  type        = string
}

variable "state_lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "cap-terraform-state-lock"
}

variable "allowed_regions" {
  description = "List of AWS regions allowed via SCP"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}
