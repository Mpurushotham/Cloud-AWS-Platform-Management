# Lab layer 04 — sample workload.
#
# Resource files:
#   data.tf          — DynamoDB table
#   compute.tf       — Lambda function and its execution role
#   api.tf           — HTTP API, routes, stage, throttling
#   observability.tf — log groups, alarms, dashboard, alarm topic
#   ssm.tf           — parameters published for the CDK layer to consume
#
# Everything here is inside the AWS free tier: Lambda's 1M monthly requests,
# API Gateway's 1M monthly HTTP API calls, and DynamoDB on-demand at
# negligible volume.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  name_prefix = "cap-${var.environment}"

  function_name = "${local.name_prefix}-api"
  table_name    = "${local.name_prefix}-items"
}
