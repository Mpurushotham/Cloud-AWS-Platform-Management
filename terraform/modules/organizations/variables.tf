variable "org_domain" {
  description = "Root domain for the AWS Organization (used for account emails)"
  type        = string
}

variable "management_account_id" {
  description = "AWS account ID of the management account"
  type        = string
}

variable "allowed_regions" {
  description = "List of AWS regions permitted by SCP (all others denied)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "member_accounts" {
  description = "Map of account name to email and parent OU"
  type = map(object({
    email     = string
    parent_ou = string
  }))
}
