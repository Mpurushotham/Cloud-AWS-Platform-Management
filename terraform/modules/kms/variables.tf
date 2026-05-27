variable "project" { description = "Project name"; type = string }
variable "environment" { description = "Environment name"; type = string }
variable "cost_center" { description = "Cost center"; type = string }
variable "owner" { description = "Owner team"; type = string }
variable "cross_account_arns" { description = "ARNs allowed cross-account key usage"; type = list(string); default = [] }
