resource "aws_sns_topic" "findings" {
  name              = "${var.environment}-security-hub-findings"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_cloudwatch_event_rule" "critical_findings" {
  name        = "${var.environment}-security-hub-critical-findings"
  description = "Route Security Hub CRITICAL/HIGH findings to SNS"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["CRITICAL", "HIGH"] }
        Workflow  = { Status = ["NEW"] }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "findings_sns" {
  rule = aws_cloudwatch_event_rule.critical_findings.name
  arn  = aws_sns_topic.findings.arn
}

resource "aws_sns_topic_subscription" "pagerduty" {
  count     = var.sns_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.findings.arn
  protocol  = "https"
  endpoint  = var.sns_endpoint
}
