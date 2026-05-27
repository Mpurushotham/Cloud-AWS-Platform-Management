terraform {
  backend "s3" {
    bucket         = "cap-terraform-state-your-org"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cap-terraform-state-lock"
    encrypt        = true
  }
}
