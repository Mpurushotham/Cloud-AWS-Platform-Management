variable "environment" { description = "Environment name"; type = string }
variable "project" { description = "Project name"; type = string }
variable "trusted_account_ids" { description = "Account IDs allowed to assume cross-account roles"; type = list(string); default = [] }
