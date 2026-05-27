resource "aws_ecr_repository_policy" "repos" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCrossAccountPull"
      Effect    = "Allow"
      Principal = { AWS = [for id in var.allowed_account_ids : "arn:aws:iam::${id}:root"] }
      Action    = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
    }]
  })
}
