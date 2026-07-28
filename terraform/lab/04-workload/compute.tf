data "archive_file" "handler" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/handler.zip"
}

resource "aws_lambda_function" "api" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  architectures = ["arm64"] # Graviton: cheaper per GB-second than x86_64.

  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # A concurrency cap is the difference between a bug costing pennies and
  # costing the whole free-tier allowance.
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.items.name
      ENVIRONMENT = var.environment
    }
  }

  dynamic "vpc_config" {
    for_each = var.attach_to_vpc ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.app_security_group_id]
    }
  }

  tracing_config {
    # X-Ray's first 100,000 traces per month are free.
    mode = "Active"
  }

  # The log group must exist before the first invocation, otherwise Lambda
  # creates it with no retention policy and logs are kept forever.
  depends_on = [aws_cloudwatch_log_group.lambda]

  lifecycle {
    precondition {
      condition     = !var.attach_to_vpc || length(var.private_subnet_ids) > 0
      error_message = "attach_to_vpc requires private_subnet_ids from layer 03."
    }

    precondition {
      condition     = !var.attach_to_vpc || var.app_security_group_id != null
      error_message = "attach_to_vpc requires app_security_group_id from layer 03."
    }
  }
}

# ── Execution role ────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    # Confused-deputy protection: scoped to this specific function.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${local.function_name}"]
    }
  }
}

# Written by hand rather than attaching AWSLambdaBasicExecutionRole, so the log
# group is named explicitly instead of granting logs:* on every group.
resource "aws_iam_role_policy" "lambda" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  # Exactly the four table actions handler.py performs — no wildcards.
  statement {
    sid    = "AccessOwnTable"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [aws_dynamodb_table.items.arn]
  }

  statement {
    sid       = "EmitTraces"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

# Attached only when the function runs inside the VPC — it needs to create and
# delete elastic network interfaces to do so.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count = var.attach_to_vpc ? 1 : 0

  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
