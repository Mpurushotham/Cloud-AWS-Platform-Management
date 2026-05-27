provider "aws" {
  region = var.aws_region
  assume_role { role_arn = "arn:aws:iam::${var.security_account_id}:role/AWSControlTowerExecution" }
  default_tags {
    tags = { Project = "cap", Environment = "security", ManagedBy = "terraform", CostCenter = var.cost_center, Owner = "security-team" }
  }
}

module "kms" {
  source      = "../../modules/kms"
  project     = "cap"
  environment = "security"
  cost_center = var.cost_center
  owner       = "security-team"
}

module "security_hub" {
  source             = "../../modules/security-hub"
  environment        = "security"
  member_account_ids = var.member_account_ids
  enable_cis         = true
  enable_pci         = true
  enable_nist        = true
  sns_endpoint       = var.security_sns_endpoint
}

module "guardduty" {
  source                    = "../../modules/guardduty"
  member_account_emails     = var.member_account_emails
  finding_s3_bucket_arn     = var.logging_s3_bucket_arn
  kms_key_arn               = module.kms.key_arns["guardduty"]
}

module "iam_identity_center" {
  source            = "../../modules/iam-identity-center"
  instance_arn      = var.sso_instance_arn
  identity_store_id = var.sso_identity_store_id
  account_ids       = var.all_account_ids
  group_ids         = var.sso_group_ids
}
