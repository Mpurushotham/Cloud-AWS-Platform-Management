provider "aws" {
  region = var.aws_region
  assume_role { role_arn = "arn:aws:iam::${var.account_id}:role/AWSControlTowerExecution" }
  default_tags {
    tags = { Project = "cap", Environment = "dev", ManagedBy = "terraform", CostCenter = var.cost_center, Owner = var.owner_team }
  }
}

module "kms" {
  source      = "../../modules/kms"
  project     = "cap"
  environment = "dev"
  cost_center = var.cost_center
  owner       = var.owner_team
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = "cap"
  environment = "dev"
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count
  kms_key_arn = module.kms.key_arns["cloudwatch"]
  cost_center = var.cost_center
  owner       = var.owner_team
}

module "vpc_endpoints" {
  source      = "../../modules/vpc-endpoints"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.isolated_subnet_ids
  vpc_cidr    = var.vpc_cidr
  environment = "dev"
  project     = "cap"
}

module "security_groups" {
  source      = "../../modules/security-groups"
  vpc_id      = module.vpc.vpc_id
  environment = "dev"
  project     = "cap"
}

module "waf" {
  source      = "../../modules/waf"
  environment = "dev"
  project     = "cap"
  scope       = "REGIONAL"
  rate_limit  = var.waf_rate_limit
}

module "eks" {
  source             = "../../modules/eks"
  project            = "cap"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  kms_key_arn        = module.kms.key_arns["eks"]
  cluster_version    = var.eks_cluster_version
  node_group_configs = var.eks_node_groups
}

module "ecs" {
  source             = "../../modules/ecs"
  project            = "cap"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  kms_key_arn        = module.kms.key_arns["ecs"]
}

module "rds" {
  source                     = "../../modules/rds"
  project                    = "cap"
  environment                = "dev"
  engine                     = "postgres"
  engine_version             = "16.3"
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  kms_key_arn                = module.kms.key_arns["rds"]
  db_subnet_ids              = module.vpc.isolated_subnet_ids
  allowed_security_group_ids = [module.security_groups.sg_id_map["eks-nodes"], module.security_groups.sg_id_map["ecs"]]
}

module "cloudwatch" {
  source      = "../../modules/cloudwatch"
  project     = "cap"
  environment = "dev"
  kms_key_arn = module.kms.key_arns["cloudwatch"]
  alarm_actions = [var.ops_sns_topic_arn]
}
