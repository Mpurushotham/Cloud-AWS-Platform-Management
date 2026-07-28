# The organization pre-dates this configuration and is adopted by import:
#   terraform import aws_organizations_organization.this o-xxxxxxxxxx
#
# prevent_destroy is not optional here. Destroying this resource would attempt
# to delete the entire AWS Organization.

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  # Trusted access for the services that operate organization-wide.
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    "account.amazonaws.com",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_organizations_organization" "current" {
  depends_on = [aws_organizations_organization.this]
}
