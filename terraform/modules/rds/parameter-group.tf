resource "aws_db_parameter_group" "main" {
  name   = "${var.project}-${var.environment}-rds-params"
  family = "${var.engine}16"

  parameter { name = "log_connections"; value = "1" }
  parameter { name = "log_disconnections"; value = "1" }
  parameter { name = "log_checkpoints"; value = "1" }
  parameter { name = "log_lock_waits"; value = "1" }
  parameter { name = "log_min_duration_statement"; value = "1000" }
  parameter { name = "rds.force_ssl"; value = "1" }

  tags = { Project = var.project, Environment = var.environment }
}
