provider "aws" {
  region = var.aws_region
  assume_role { role_arn = "arn:aws:iam::${var.logging_account_id}:role/AWSControlTowerExecution" }
  default_tags {
    tags = { Project = "cap", Environment = "logging", ManagedBy = "terraform", CostCenter = var.cost_center, Owner = "security-team" }
  }
}

module "kms" {
  source      = "../../modules/kms"
  project     = "cap"
  environment = "logging"
  cost_center = var.cost_center
  owner       = "security-team"
}

module "s3_audit" {
  source       = "../../modules/s3"
  project      = "cap"
  environment  = "logging"
  bucket_suffix = "audit-logs"
  kms_key_arn  = module.kms.key_arns["s3"]
  versioning_enabled = true
  lifecycle_rules = [{
    id            = "glacier-transition"
    enabled       = true
    transition_days     = 90
    transition_class    = "GLACIER"
    expiration_days     = 2555
  }]
}

module "cloudtrail" {
  source            = "../../modules/cloudtrail"
  environment       = "logging"
  kms_key_arn       = module.kms.key_arns["cloudtrail"]
  s3_bucket_id      = module.s3_audit.bucket_id
  s3_bucket_arn     = module.s3_audit.bucket_arn
  log_retention_days = 365
}

module "aws_config" {
  source                  = "../../modules/aws-config"
  environment             = "logging"
  s3_bucket_id            = module.s3_audit.bucket_id
  kms_key_arn             = module.kms.key_arns["config"]
  sns_topic_arn           = var.config_sns_topic_arn
  aggregator_account_id   = var.logging_account_id
  is_aggregator           = true
}
