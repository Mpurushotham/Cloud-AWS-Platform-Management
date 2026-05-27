variable "aws_region" { description = "AWS region"; type = string; default = "us-east-1" }
variable "account_id" { description = "staging account ID"; type = string }
variable "cost_center" { description = "Cost center"; type = string }
variable "owner_team" { description = "Owning team name"; type = string; default = "platform-team" }
variable "vpc_cidr" { description = "VPC CIDR block"; type = string }
variable "az_count" { description = "Number of AZs"; type = number; default = 3 }
variable "waf_rate_limit" { description = "WAF rate limit (requests per 5min per IP)"; type = number; default = 2000 }
variable "eks_cluster_version" { description = "Kubernetes version"; type = string; default = "1.30" }
variable "eks_node_groups" { description = "EKS node group configurations"; type = any }
variable "rds_instance_class" { description = "RDS instance class"; type = string }
variable "rds_allocated_storage" { description = "RDS allocated storage in GB"; type = number }
variable "ops_sns_topic_arn" { description = "SNS topic ARN for operational alerts"; type = string }
