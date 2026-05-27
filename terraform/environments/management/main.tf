provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cap"
      Environment = "management"
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
      Owner       = "platform-team"
    }
  }
}

module "organizations" {
  source = "../../modules/organizations"

  org_domain            = var.org_domain
  management_account_id = var.management_account_id
  allowed_regions       = var.allowed_regions

  member_accounts = {
    landing_zone    = { email = var.account_emails.landing_zone, parent_ou = "core" }
    security        = { email = var.account_emails.security, parent_ou = "core" }
    logging         = { email = var.account_emails.logging, parent_ou = "core" }
    shared_services = { email = var.account_emails.shared_services, parent_ou = "infrastructure" }
    dev             = { email = var.account_emails.dev, parent_ou = "non-prod" }
    staging         = { email = var.account_emails.staging, parent_ou = "non-prod" }
    prod            = { email = var.account_emails.prod, parent_ou = "prod" }
    sandbox         = { email = var.account_emails.sandbox, parent_ou = "sandbox" }
  }
}

module "control_tower" {
  source = "../../modules/control-tower"

  log_archive_account_id = module.organizations.account_ids["logging"]
  audit_account_id       = module.organizations.account_ids["security"]
  governed_regions       = var.allowed_regions

  depends_on = [module.organizations]
}
