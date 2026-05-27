provider "aws" {
  region = var.aws_region
  assume_role { role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/AWSControlTowerExecution" }
  default_tags {
    tags = { Project = "cap", Environment = "shared-services", ManagedBy = "terraform", CostCenter = var.cost_center, Owner = "platform-team" }
  }
}

module "kms" {
  source      = "../../modules/kms"
  project     = "cap"
  environment = "shared-services"
  cost_center = var.cost_center
  owner       = "platform-team"
}

module "ecr" {
  source              = "../../modules/ecr"
  project             = "cap"
  environment         = "shared"
  repository_names    = var.ecr_repository_names
  allowed_account_ids = var.workload_account_ids
}

module "route53" {
  source      = "../../modules/route53"
  domain_name = var.internal_domain
  vpc_id      = var.shared_vpc_id
  environment = "shared"
  resolver_subnet_ids = var.resolver_subnet_ids
}

module "acm" {
  source                  = "../../modules/acm"
  domain_name             = var.public_domain
  subject_alternative_names = ["*.${var.public_domain}", "api.${var.public_domain}"]
  route53_zone_id         = module.route53.zone_id
}

module "transit_gateway" {
  source              = "../../modules/transit-gateway"
  environment_vpc_ids    = var.spoke_vpc_ids
  environment_subnet_ids = var.spoke_subnet_ids
  account_ids            = var.workload_account_ids
}
