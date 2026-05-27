resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-rds-subnet-group"
  subnet_ids = var.db_subnet_ids
  tags       = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}
