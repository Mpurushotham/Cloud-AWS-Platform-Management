output "repository_urls" { value = { for k, v in aws_ecr_repository.repos : k => v.repository_url } }
output "registry_id" { value = data.aws_caller_identity.current.account_id }
