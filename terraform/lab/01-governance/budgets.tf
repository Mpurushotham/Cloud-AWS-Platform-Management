# Cost guardrail.
#
# AWS provides the first two budgets per account free of charge; beyond that
# each costs $0.02/day. This layer creates exactly one, and the account already
# has a zero-spend budget, so the pair stays inside the free allowance.
#
# The forecast notification is the important one: it fires before money is
# actually spent, which is what makes it useful as a lab guardrail.

resource "aws_budgets_budget" "lab_monthly" {
  name         = "cap-lab-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit             = false
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = false
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }

  # Actual spend crossed a tenth of the ceiling — something billable is running.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 10
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  # Forecast to exceed the ceiling — act before the money is spent.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }
}
