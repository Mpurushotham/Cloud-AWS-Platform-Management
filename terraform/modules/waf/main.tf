resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project}-${var.environment}-waf"
  scope = var.scope

  default_action { allow {} }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
