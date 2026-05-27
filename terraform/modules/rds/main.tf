resource "aws_db_instance" "main" {
  identifier     = "${var.project}-${var.environment}-rds"
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 3
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az               = var.environment == "prod" ? true : false
  publicly_accessible    = false
  deletion_protection    = var.environment == "prod" ? true : false
  skip_final_snapshot    = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project}-${var.environment}-final-snapshot" : null

  backup_retention_period = var.environment == "prod" ? 35 : 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.environment == "prod" ? 731 : 7

  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
  manage_master_user_password = true
  master_username             = "dbadmin"

  tags = local.common_tags
}

resource "aws_iam_role" "enhanced_monitoring" {
  name = "${var.project}-${var.environment}-rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "monitoring.rds.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

locals {
  common_tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
