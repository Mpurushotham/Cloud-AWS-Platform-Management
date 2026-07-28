variable "aws_region" {
  description = "Primary AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "cost_center" {
  description = "Cost centre tag applied to every resource"
  type        = string
  default     = "lab"
}

variable "owner_team" {
  description = "Owning team tag applied to every resource"
  type        = string
  default     = "platform-team"
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "Cloud-AWS-Platform-Management"
}

variable "apply_branch" {
  description = "Branch permitted to assume the apply and image-push roles"
  type        = string
  default     = "main"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket for Terraform remote state. Leave null to derive
    cap-lab-tfstate-<account-id>.
  EOT
  type        = string
  default     = null
}

variable "state_lock_table_name" {
  description = "DynamoDB table used for Terraform state locking"
  type        = string
  default     = "cap-lab-terraform-state-lock"
}

variable "access_log_bucket_name" {
  description = <<-EOT
    Central S3 server access log bucket, from the governance layer output
    access_logs_bucket_name.
  EOT
  type        = string
}

variable "state_encryption" {
  description = <<-EOT
    Server-side encryption for the state bucket.

    "AES256"  — S3-managed keys. No monthly charge. The lab default.
    "aws:kms" — customer-managed key with rotation. Stronger key isolation and
                an auditable key policy, but a CMK costs $1/month, which the
                zero-cost lab budget does not allow.

    Terraform state contains resource attributes that may include secrets, so
    production deployments should use "aws:kms". See ADR-0015.
  EOT
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.state_encryption)
    error_message = "state_encryption must be either AES256 or aws:kms."
  }
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the GitHub OIDC identity provider. Set false when another stack in
    the same account already registered token.actions.githubusercontent.com,
    since an account may hold only one provider per URL.
  EOT
  type        = bool
  default     = true
}
