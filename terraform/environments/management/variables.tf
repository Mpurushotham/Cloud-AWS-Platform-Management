variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "org_domain" {
  description = "Root domain for the AWS Organization"
  type        = string
}

variable "management_account_id" {
  description = "AWS account ID of the management account"
  type        = string
}

variable "cost_center" {
  description = "Cost center tag value"
  type        = string
}

variable "allowed_regions" {
  description = "Allowed AWS regions (enforced via SCP)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "account_emails" {
  description = "Email addresses for each member account"
  type = object({
    landing_zone    = string
    security        = string
    logging         = string
    shared_services = string
    dev             = string
    staging         = string
    prod            = string
    sandbox         = string
  })
}
