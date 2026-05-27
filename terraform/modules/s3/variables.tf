variable "project" { description = "Project name"; type = string }
variable "environment" { description = "Environment name"; type = string }
variable "bucket_suffix" { description = "Suffix appended to bucket name after project-environment-"; type = string }
variable "kms_key_arn" { description = "KMS key ARN for bucket encryption"; type = string }
variable "versioning_enabled" { description = "Enable versioning"; type = bool; default = true }
variable "prevent_destroy" { description = "Prevent bucket destruction via lifecycle"; type = bool; default = false }
variable "cost_center" { description = "Cost center tag"; type = string; default = "" }
variable "owner" { description = "Owner tag"; type = string; default = "" }
variable "lifecycle_rules" {
  description = "S3 lifecycle rules"
  type = list(object({
    id              = string
    enabled         = bool
    transition_days = number
    transition_class = string
    expiration_days = number
  }))
  default = []
}
