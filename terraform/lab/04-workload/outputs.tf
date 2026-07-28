output "api_endpoint" {
  description = "Base URL of the sample API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  description = "HTTP API identifier"
  value       = aws_apigatewayv2_api.main.id
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.items.name
}

output "alarm_topic_arn" {
  description = "SNS topic receiving alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard for the sample workload"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "ssm_parameter_names" {
  description = "Parameters published for the CDK layer"
  value       = [for p in aws_ssm_parameter.handoff : p.name]
}

output "smoke_test" {
  description = "Commands that prove the whole request path works."
  value       = <<-EOT
    ENDPOINT="${aws_apigatewayv2_stage.default.invoke_url}"

    curl -sS "$ENDPOINT/health"
    curl -sS -X POST "$ENDPOINT/items" -H 'content-type: application/json' -d '{"name":"first"}'
    curl -sS "$ENDPOINT/items"
  EOT
}
