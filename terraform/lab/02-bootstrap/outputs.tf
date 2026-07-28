output "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state"
  value       = aws_s3_bucket.state.id
}

output "state_lock_table_name" {
  description = "DynamoDB table used for state locking"
  value       = aws_dynamodb_table.state_lock.name
}

output "state_kms_key_arn" {
  description = "KMS key encrypting state, or null when using S3-managed keys"
  value       = local.use_kms ? aws_kms_key.state[0].arn : null
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC identity provider ARN"
  value       = local.oidc_provider_arn
}

output "ci_role_arns" {
  description = "Role ARNs to configure as GitHub repository variables"
  value = {
    plan       = aws_iam_role.terraform_plan.arn
    apply      = aws_iam_role.terraform_apply.arn
    image_push = aws_iam_role.image_push.arn
    prowler    = aws_iam_role.prowler.arn
  }
}

output "backend_config" {
  description = "Backend block for the layers that store state in this bucket."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "<layer>/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.state_lock.name}"
        encrypt        = true
      }
    }
  EOT
}

output "github_cli_commands" {
  description = "Register the role ARNs with the GitHub repository in one step."
  value       = <<-EOT
    gh variable set AWS_REGION           --body "${var.aws_region}"
    gh variable set AWS_ACCOUNT_ID       --body "${local.account_id}"
    gh variable set AWS_PLAN_ROLE_ARN    --body "${aws_iam_role.terraform_plan.arn}"
    gh variable set AWS_APPLY_ROLE_ARN   --body "${aws_iam_role.terraform_apply.arn}"
    gh variable set AWS_IMAGE_PUSH_ROLE_ARN --body "${aws_iam_role.image_push.arn}"
    gh variable set AWS_PROWLER_ROLE_ARN --body "${aws_iam_role.prowler.arn}"
    gh variable set TF_STATE_BUCKET      --body "${aws_s3_bucket.state.id}"
    gh variable set TF_STATE_LOCK_TABLE  --body "${aws_dynamodb_table.state_lock.name}"
  EOT
}
