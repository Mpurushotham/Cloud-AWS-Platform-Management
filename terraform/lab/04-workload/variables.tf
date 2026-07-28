variable "aws_region" {
  description = "Primary AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in the cap-{env}-{component} naming convention"
  type        = string
  default     = "lab"
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

variable "log_retention_days" {
  description = "CloudWatch retention for the function and API logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Must be a retention period CloudWatch Logs accepts."
  }
}

variable "lambda_memory_mb" {
  description = "Function memory. The free tier is measured in GB-seconds, so smaller is cheaper."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 1024
    error_message = "Keep lab memory between 128 MB and 1024 MB."
  }
}

variable "lambda_timeout_seconds" {
  description = "Function timeout"
  type        = number
  default     = 10
}

variable "reserved_concurrency" {
  description = <<-EOT
    Maximum concurrent executions. Capped in the lab so that a runaway loop or
    an unauthenticated flood cannot consume the monthly free-tier allowance in
    minutes. Set to -1 to remove the cap.
  EOT
  type        = number
  default     = 5
}

variable "api_throttle_burst" {
  description = "API Gateway burst limit — the second half of the runaway-cost guardrail"
  type        = number
  default     = 10
}

variable "api_throttle_rate" {
  description = "API Gateway steady-state request rate per second"
  type        = number
  default     = 5
}

variable "alarm_email" {
  description = <<-EOT
    Address subscribed to the alarm topic. Leave null to create the topic
    without a subscription — useful when the endpoint is wired up elsewhere.
  EOT
  type        = string
  default     = null
}

variable "attach_to_vpc" {
  description = <<-EOT
    Run the function inside the private subnets from layer 03.

    Left false on purpose. The lab VPC has no NAT gateway, so a VPC-attached
    function can reach S3 and DynamoDB through gateway endpoints but nothing
    else — including the STS and CloudWatch endpoints the runtime itself uses.
    Enabling this without also enabling NAT or interface endpoints will produce
    timeouts that look like application bugs.
  EOT
  type        = bool
  default     = false
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from layer 03. Required when attach_to_vpc is true."
  type        = list(string)
  default     = []
}

variable "app_security_group_id" {
  description = "Application security group from layer 03. Required when attach_to_vpc is true."
  type        = string
  default     = null
}
