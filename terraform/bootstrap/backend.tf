# Initially use local backend.
# After first apply, migrate with: terraform init -migrate-state
# Then replace this file content with the S3 backend configuration below.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# S3 backend (activate after first apply):
# terraform {
#   backend "s3" {
#     bucket         = "<state_bucket_name>"
#     key            = "bootstrap/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "cap-terraform-state-lock"
#     encrypt        = true
#     kms_key_id     = "<kms_key_arn>"
#   }
# }
