# aws_wafv2_web_acl_rule is not a resource type the AWS provider offers -- WAFv2
# rules are declared inline on aws_wafv2_web_acl. A block using it was present
# here with a comment acknowledging exactly that, which left the whole module
# failing `terraform validate`. The rules now live in main.tf as intended.

# ── AWS managed rule groups ───────────────────────────────────────────────────
#
# The web ACL previously had no rules at all: default_action was allow and
# nothing evaluated a request. A WAF in that state costs money and inspects
# nothing, which is worse than no WAF because it reads as protection.
#
# Priorities are spaced by 10 so custom rules can be inserted between them.

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [var.log_destination_arn]

  # Do not persist credentials or session material into the WAF logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
