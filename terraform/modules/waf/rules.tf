resource "aws_wafv2_web_acl_rule" "common" {
  name       = "AWSManagedRulesCommonRuleSet"
  priority   = 10
  web_acl_id = aws_wafv2_web_acl.main.id
  scope      = var.scope

  override_action { none {} }

  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesCommonRuleSet"
      vendor_name = "AWS"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-common-rules"
    sampled_requests_enabled   = true
  }
}

# Note: aws_wafv2_web_acl_rule is not a real resource — rules are inline on aws_wafv2_web_acl
# This file demonstrates the rule structure; the actual implementation uses dynamic blocks in main.tf
