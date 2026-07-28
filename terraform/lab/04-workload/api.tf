# HTTP API rather than REST API: roughly a third of the price per million
# requests, lower latency, and everything this workload needs. REST API earns
# its cost when you need request validation, WAF association or usage plans.

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
  description   = "Sample platform API — proves the request path end to end"

  # No cors_configuration: this API has no browser clients. An open CORS policy
  # is a common default that quietly makes an API callable from any origin.
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = var.lambda_timeout_seconds * 1000
}

locals {
  # Routes are enumerated explicitly. A catch-all "$default" route would send
  # every unmatched path to the function, including probes for well-known
  # exploit paths, and bill for each one.
  routes = [
    "GET /health",
    "GET /items",
    "POST /items",
  ]
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = toset(local.routes)

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Throttling is the primary cost guardrail. Combined with the function's
  # reserved concurrency it bounds worst-case spend from an unauthenticated
  # flood at a few dollars rather than an open-ended bill.
  default_route_settings {
    throttling_burst_limit   = var.api_throttle_burst
    throttling_rate_limit    = var.api_throttle_rate
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
      latencyMs      = "$context.responseLatency"
    })
  }
}

# Permission for API Gateway to invoke the function. source_arn confines it to
# this API — without it, any API in the account could invoke the function.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
