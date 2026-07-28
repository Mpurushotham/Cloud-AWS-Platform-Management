variable "project" {
  description = "Project name"
  type        = string
}
variable "environment" {
  description = "Environment name"
  type        = string
}
variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "private_subnet_ids" {
  description = "Private subnet IDs for node groups"
  type        = list(string)
}
variable "kms_key_arn" {
  description = "KMS key ARN for secrets encryption and EBS volumes"
  type        = string
}
variable "node_group_configs" {
  description = "Map of node group name to configuration"
  type = map(object({
    instance_type = string
    min_size      = number
    max_size      = number
    desired_size  = number
    capacity_type = optional(string, "ON_DEMAND")
  }))
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDRs permitted to reach the public API server endpoint in non-production.
    Production is private-only and ignores this. Defaults to an empty list,
    which AWS rejects -- callers must supply their egress ranges deliberately
    rather than inheriting an open endpoint by omission.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 defeats the purpose of an allow-list. Use private-only access instead."
  }
}
