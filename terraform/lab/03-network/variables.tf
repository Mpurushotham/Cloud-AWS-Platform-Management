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

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be /20 or larger to fit the three subnet tiers."
  }
}

variable "az_count" {
  description = <<-EOT
    Availability Zones to span. Two is enough to demonstrate multi-AZ layout
    while keeping the subnet count small; production uses three.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create NAT gateways for private-subnet egress.

    Left false in the lab: a NAT gateway costs roughly $32/month per AZ plus
    data processing, and each attached Elastic IP adds $3.60/month. Private
    workloads reach S3 and DynamoDB through free gateway endpoints instead.
    Anything needing general internet egress must run outside the VPC.
  EOT
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = <<-EOT
    Create interface VPC endpoints (SSM, ECR, Secrets Manager, and so on).

    Left false in the lab: interface endpoints bill about $0.01 per hour each,
    so the ten endpoints the production design specifies would cost roughly
    $73/month before data charges. Gateway endpoints for S3 and DynamoDB are
    free and are always created.
  EOT
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs. Short by default to stay inside the 5 GB free tier."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.flow_log_retention_days)
    error_message = "Must be a retention period CloudWatch Logs accepts."
  }
}
