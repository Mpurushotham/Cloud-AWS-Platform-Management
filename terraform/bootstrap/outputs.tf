output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket"
  value       = aws_s3_bucket.state.arn
}

output "state_lock_table_name" {
  description = "Name of the DynamoDB state lock table"
  value       = aws_dynamodb_table.state_lock.name
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the state bucket"
  value       = aws_kms_key.state.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = local.github_oidc_arn
}

output "terraform_plan_role_arn" {
  description = "ARN of the cap-plan IAM role (Terraform plan — all branches)"
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "ARN of the cap-apply IAM role (Terraform apply — main branch only)"
  value       = aws_iam_role.terraform_apply.arn
}

output "image_push_role_arn" {
  description = "ARN of the cap-image-push IAM role (ECR push — main branch only)"
  value       = aws_iam_role.image_push.arn
}

output "prowler_role_arn" {
  description = "ARN of the cap-prowler IAM role (compliance scanning — all branches)"
  value       = aws_iam_role.prowler.arn
}
