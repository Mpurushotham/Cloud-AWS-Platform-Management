output "trail_arn" { value = aws_cloudtrail.main.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.trail.name }
