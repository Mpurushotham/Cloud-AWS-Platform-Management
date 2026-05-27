# Module: shield
# See variables.tf and outputs.tf for inputs/outputs.
# Full implementation references docs/architecture/overview.md

locals {
  common_tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

variable "project" { description = "Project name prefix"; type = string; default = "cap" }
