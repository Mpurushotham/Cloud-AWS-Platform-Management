variable "project" { description = "Project name"; type = string }
variable "environment" { description = "Environment name"; type = string }
variable "engine" { description = "Database engine (postgres, mysql)"; type = string }
variable "engine_version" { description = "Engine version"; type = string }
variable "instance_class" { description = "RDS instance class"; type = string }
variable "allocated_storage" { description = "Allocated storage in GiB"; type = number }
variable "kms_key_arn" { description = "KMS key ARN for encryption"; type = string }
variable "vpc_id" { description = "VPC ID"; type = string; default = "" }
variable "db_subnet_ids" { description = "Subnet IDs (isolated tier)"; type = list(string) }
variable "allowed_security_group_ids" { description = "Security group IDs allowed to connect"; type = list(string); default = [] }
