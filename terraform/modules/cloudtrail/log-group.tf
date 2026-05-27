resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_iam_role" "cloudtrail" {
  name = "${var.project}-${var.environment}-cloudtrail-cw-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "cloudtrail" {
  role = aws_iam_role.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.trail.arn}:*" }]
  })
}
