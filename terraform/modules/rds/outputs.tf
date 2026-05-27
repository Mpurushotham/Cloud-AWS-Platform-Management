output "endpoint" { value = aws_db_instance.main.endpoint }
output "port" { value = aws_db_instance.main.port }
output "db_identifier" { value = aws_db_instance.main.id }
output "master_user_secret_arn" { value = aws_db_instance.main.master_user_secret[0].secret_arn }
