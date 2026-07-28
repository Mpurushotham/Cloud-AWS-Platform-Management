terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cap"
      Environment = "lab"
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
      Owner       = var.owner_team
      Layer       = "lab-02-bootstrap"
    }
  }
}
