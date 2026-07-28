# Root account usage detection.
#
# ADR-0014 makes non-use of root a discipline rather than a technical control:
# nothing prevents someone signing in as root, and SCPs cannot restrict the
# management account. Detection is therefore the only control available, and
# without it a root sign-in leaves no signal anyone will see.
#
# CIS AWS Foundations Benchmark control 4.3 asks for exactly this.
#
# Cost: nothing. The trail already exists; CloudWatch Logs ingestion at lab
# volume is far inside the 5 GB free allowance, metric filters are free, and the
# account is using 5 of its 10 free alarms.

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_organization_trail ? 1 : 0

  name              = "/aws/cloudtrail/cap-lab-org-trail"
  retention_in_days = var.trail_retention_days
}

resource "aws_iam_role" "cloudtrail_to_logs" {
  count = var.enable_organization_trail ? 1 : 0

  name               = "cap-lab-cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_to_logs_trust[0].json
}

data "aws_iam_policy_document" "cloudtrail_to_logs_trust" {
  count = var.enable_organization_trail ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role_policy" "cloudtrail_to_logs" {
  count = var.enable_organization_trail ? 1 : 0

  name   = "cap-lab-cloudtrail-to-logs"
  role   = aws_iam_role.cloudtrail_to_logs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_to_logs[0].json
}

data "aws_iam_policy_document" "cloudtrail_to_logs" {
  count = var.enable_organization_trail ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"]
  }
}

# ── Detection ─────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  count = var.enable_organization_trail ? 1 : 0

  name           = "cap-lab-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  # Matches any root-principal event except the service-initiated calls AWS
  # makes on the account's behalf, which are not a human signing in as root.
  pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name          = "RootAccountUsage"
    namespace     = "CAP/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  count = var.enable_organization_trail ? 1 : 0

  alarm_name        = "cap-lab-root-account-usage"
  alarm_description = "The account root user performed an API call. Expected to be zero. See docs/adr/0014-eliminate-root-access-keys.md."

  namespace           = "CAP/Security"
  metric_name         = "RootAccountUsage"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts[0].arn]
}

resource "aws_sns_topic" "security_alerts" {
  count = var.enable_organization_trail ? 1 : 0

  name = "cap-lab-security-alerts"
}

resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_organization_trail ? 1 : 0

  arn    = aws_sns_topic.security_alerts[0].arn
  policy = data.aws_iam_policy_document.security_alerts[0].json
}

data "aws_iam_policy_document" "security_alerts" {
  count = var.enable_organization_trail ? 1 : 0

  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.enable_organization_trail && length(var.budget_notification_emails) > 0 ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.budget_notification_emails[0]
}
