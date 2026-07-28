# Terraform → CDK handoff.
#
# The project convention is that Terraform owns foundational resources and
# publishes their identifiers to SSM Parameter Store; CDK stacks read them at
# synth time. This avoids both remote state coupling (CDK would need Terraform
# state credentials) and CloudFormation exports (which cannot be deleted while
# anything imports them, producing undeletable stacks).
#
# Standard-tier parameters are free and unlimited in practice.

locals {
  ssm_prefix = "/cap/${var.environment}"

  handoff_parameters = {
    "api/id"            = aws_apigatewayv2_api.main.id
    "api/endpoint"      = aws_apigatewayv2_stage.default.invoke_url
    "api/execution-arn" = aws_apigatewayv2_api.main.execution_arn
    "table/name"        = aws_dynamodb_table.items.name
    "table/arn"         = aws_dynamodb_table.items.arn
    "function/name"     = aws_lambda_function.api.function_name
    "function/arn"      = aws_lambda_function.api.arn
    "alarms/topic-arn"  = aws_sns_topic.alarms.arn
  }
}

resource "aws_ssm_parameter" "handoff" {
  for_each = local.handoff_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value

  description = "Published by terraform/lab/04-workload for consumption by the CDK layer"
  tier        = "Standard"

  tags = { Name = "${local.ssm_prefix}/${each.key}" }
}
