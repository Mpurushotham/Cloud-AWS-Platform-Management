output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "List of isolated subnet IDs (databases only, no internet route)"
  value       = aws_subnet.isolated[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (one per AZ)"
  value       = aws_nat_gateway.main[*].id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC flow logs"
  value       = aws_cloudwatch_log_group.flow_log.name
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}
