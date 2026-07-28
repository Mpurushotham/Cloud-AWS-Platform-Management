# Account-wide baseline controls. All of these are free of charge and map
# directly to CIS AWS Foundations Benchmark v3.0 controls.

# CIS 1.8, 1.9 — password policy.
resource "aws_iam_account_password_policy" "baseline" {
  minimum_password_length        = var.password_minimum_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
  hard_expiry                    = false
}

# CIS 2.1.4 — block public access at the account level, so that no bucket in
# this account can be made public regardless of its own configuration.
resource "aws_s3_account_public_access_block" "baseline" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CIS 2.2.1 — EBS encryption by default for every volume created in the region.
resource "aws_ebs_encryption_by_default" "baseline" {
  enabled = true
}

# IMDSv2 required by default on new EC2 instances in this region, so an
# instance cannot opt out of it by omitting the setting.
resource "aws_ec2_instance_metadata_defaults" "baseline" {
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
  instance_metadata_tags      = "enabled"
}
