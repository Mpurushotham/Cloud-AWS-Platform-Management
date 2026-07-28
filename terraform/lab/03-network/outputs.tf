output "vpc_id" {
  description = "Lab VPC identifier"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Lab VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs, one per AZ"
  value       = aws_subnet.isolated[*].id
}

output "db_subnet_group_name" {
  description = "DB subnet group spanning the isolated tier"
  value       = aws_db_subnet_group.isolated.name
}

output "security_group_ids" {
  description = "Security group IDs, keyed by tier"
  value = {
    alb           = aws_security_group.alb.id
    app           = aws_security_group.app.id
    data          = aws_security_group.data.id
    vpc_endpoints = aws_security_group.vpc_endpoints.id
  }
}

output "has_internet_egress" {
  description = <<-EOT
    Whether private subnets can reach the internet. False in the lab: there is
    no NAT gateway, so workloads in the private tier reach S3 and DynamoDB
    through gateway endpoints and nothing else.
  EOT
  value       = var.enable_nat_gateway
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}
