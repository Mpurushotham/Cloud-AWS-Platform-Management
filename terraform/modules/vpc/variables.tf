variable "project" {
  description = "Project name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to use (2 or 3)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "kms_key_arn" {
  description = "ARN of KMS key for CloudWatch Logs encryption (VPC flow logs)"
  type        = string
}

variable "cost_center" {
  description = "Cost center tag value"
  type        = string
}

variable "owner" {
  description = "Owner team tag value"
  type        = string
}
