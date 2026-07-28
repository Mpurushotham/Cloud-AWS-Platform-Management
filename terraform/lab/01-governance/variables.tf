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

# The approved-region list is not a variable here on purpose. It lives in
# security/scps/deny-region-restriction.json so that the committed policy
# document remains the single source of truth for what the guardrail enforces.

variable "trail_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket name for CloudTrail logs. Leave null to derive
    cap-lab-cloudtrail-<account-id> automatically.
  EOT
  type        = string
  default     = null
}

variable "trail_retention_days" {
  description = <<-EOT
    Days before CloudTrail objects expire. Kept short in the lab so that the
    S3 free-tier allowance (5 GB) is never approached.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.trail_retention_days >= 7
    error_message = "Retain at least 7 days of audit log, otherwise the trail has no investigative value."
  }
}

variable "budget_limit_usd" {
  description = <<-EOT
    Monthly cost ceiling for the forecast alarm. The lab is designed to stay at
    $0, so any forecast above this indicates a billable resource was introduced.
  EOT
  type        = number
  default     = 5
}

variable "budget_notification_emails" {
  description = "Addresses notified when actual or forecast spend breaches the budget"
  type        = list(string)

  validation {
    condition     = length(var.budget_notification_emails) > 0
    error_message = "At least one address must receive budget alerts, otherwise the cost guardrail is silent."
  }
}

variable "enable_organization_trail" {
  description = <<-EOT
    Create the CloudTrail organization trail. A single trail logging management
    events is free; data events are not enabled by this layer.
  EOT
  type        = bool
  default     = true
}

variable "attach_scps" {
  description = <<-EOT
    Attach Service Control Policies to the root and OUs. Note that the
    Organizations management account is exempt from SCP enforcement by AWS
    design, so in a single-account lab these attachments are structurally
    correct but do not restrict anything. See README.md.
  EOT
  type        = bool
  default     = true
}
