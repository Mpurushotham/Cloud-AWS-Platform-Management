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

variable "account_alias" {
  description = <<-EOT
    IAM account alias, which replaces the 12-digit account ID in the console
    sign-in URL: https://<alias>.signin.aws.amazon.com/console

    Must be globally unique across all AWS accounts, 3-63 characters, lowercase
    alphanumeric and hyphens only, not starting or ending with a hyphen. Free.
    Set to null to leave the alias unset.
  EOT
  type        = string
  default     = null

  validation {
    condition = var.account_alias == null || can(regex(
      "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.account_alias
    ))
    error_message = "Alias must be 3-63 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "human_user_name" {
  description = <<-EOT
    IAM user that signs in day to day. Receives a policy granting only
    self-credential management and the right to assume cap-platform-admin.

    Attaching that policy is additive and safe. Removing whatever broad
    permissions the user already holds is a separate, manual step that must
    follow successful MFA enrolment -- see README.md. Set to null to skip.
  EOT
  type        = string
  default     = null
}

variable "break_glass_principal_arns" {
  description = <<-EOT
    IAM principals allowed to assume cap-platform-admin. These must be IAM users or
    roles that already exist — never the account root. MFA is enforced on assumption.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.break_glass_principal_arns) > 0
    error_message = "At least one non-root principal must be able to assume cap-platform-admin, otherwise the role is unusable."
  }

  validation {
    condition     = alltrue([for arn in var.break_glass_principal_arns : !endswith(arn, ":root")])
    error_message = "Account root must not be granted assume access. Retiring root usage is the entire point of this layer."
  }
}

variable "max_session_duration_seconds" {
  description = "Maximum STS session length for cap-platform-admin"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration_seconds >= 900 && var.max_session_duration_seconds <= 14400
    error_message = "Session duration must be between 900 (15m) and 14400 (4h) seconds."
  }
}

variable "password_minimum_length" {
  description = "Minimum console password length (CIS AWS Foundations 1.8 requires >= 14)"
  type        = number
  default     = 14

  validation {
    condition     = var.password_minimum_length >= 14
    error_message = "CIS AWS Foundations Benchmark control 1.8 requires a minimum password length of 14."
  }
}
