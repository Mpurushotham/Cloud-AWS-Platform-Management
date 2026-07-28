# VPC flow logs.
#
# Delivered to CloudWatch Logs with short retention. An idle lab VPC produces a
# negligible volume, well inside the 5 GB free ingestion allowance. Traffic-heavy
# environments should send flow logs to S3 instead, which is materially cheaper
# per GB than CloudWatch ingestion.

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = var.flow_log_retention_days
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust.json
}

data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # Confused-deputy protection: this role is assumable only on behalf of a
    # flow log belonging to this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${local.name_prefix}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  # One-minute aggregation makes rejected connections visible quickly enough to
  # be useful during an investigation.
  max_aggregation_interval = 60
}
