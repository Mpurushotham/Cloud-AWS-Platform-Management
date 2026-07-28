resource "aws_wafv2_web_acl" "main" {
  #checkov:skip=CKV_AWS_192:Log4Shell JNDI signatures are covered by AWSManagedRulesKnownBadInputsRuleSet, attached in the dynamic rule block below
  name  = "${var.project}-${var.environment}-waf"
  scope = var.scope

  default_action {
    allow {}
  }

  # Baseline protections. KnownBadInputs is what covers Log4Shell
  # (CVE-2021-44228) via its JNDI lookup signatures.
  dynamic "rule" {
    for_each = {
      AWSManagedRulesCommonRuleSet          = 10
      AWSManagedRulesKnownBadInputsRuleSet  = 20
      AWSManagedRulesAmazonIpReputationList = 30
      AWSManagedRulesSQLiRuleSet            = 40
    }

    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # Rate limiting sits after the managed groups so obviously-bad requests are
  # rejected before they consume the rate budget.
  rule {
    name     = "RateLimitPerIP"
    priority = 100

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
