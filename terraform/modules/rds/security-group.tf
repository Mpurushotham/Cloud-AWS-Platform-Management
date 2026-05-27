resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS security group — allow only from approved compute SGs"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Allow PostgreSQL from approved SG"
    }
  }

  tags = { Project = var.project, Environment = var.environment, Name = "${var.project}-${var.environment}-rds-sg" }
}
