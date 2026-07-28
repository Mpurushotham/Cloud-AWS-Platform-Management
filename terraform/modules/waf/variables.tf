variable "project" {
  description = "Project name"
  type        = string
}
variable "environment" {
  description = "Environment name"
  type        = string
}
variable "scope" {
  description = "WAF scope: REGIONAL or CLOUDFRONT"
  type        = string
  default     = "REGIONAL"
}
variable "rate_limit" {
  description = "Rate limit (requests per 5-min window per IP)"
  type        = number
  default     = 2000
}
variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block"
  type        = list(string)
  default     = []
}

variable "log_destination_arn" {
  description = <<-EOT
    Kinesis Firehose delivery stream or CloudWatch log group ARN receiving WAF
    logs. A web ACL without logging gives no evidence after an incident.
  EOT
  type        = string
}
