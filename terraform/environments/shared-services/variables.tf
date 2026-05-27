variable "aws_region" { description = "AWS region"; type = string; default = "us-east-1" }
variable "shared_services_account_id" { description = "Shared services account ID"; type = string }
variable "cost_center" { description = "Cost center tag"; type = string }
variable "ecr_repository_names" { description = "ECR repository names to create"; type = list(string) }
variable "workload_account_ids" { description = "Account IDs allowed to pull from ECR"; type = list(string) }
variable "internal_domain" { description = "Internal DNS domain (e.g., cap.internal)"; type = string }
variable "public_domain" { description = "Public domain for ACM certificates"; type = string }
variable "shared_vpc_id" { description = "Shared services VPC ID for Route53 association"; type = string }
variable "resolver_subnet_ids" { description = "Subnet IDs for Route53 Resolver endpoints"; type = list(string) }
variable "spoke_vpc_ids" { description = "Map of env→VPC ID for TGW attachments"; type = map(string) }
variable "spoke_subnet_ids" { description = "Map of env→subnet IDs for TGW attachments"; type = map(list(string)) }
