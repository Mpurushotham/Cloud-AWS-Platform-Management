resource "aws_ecr_lifecycle_policy" "repos" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    rules = [
      { rulePriority = 1, description = "Expire untagged images after 7 days", selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }, action = { type = "expire" } },
      { rulePriority = 2, description = "Keep last 10 tagged images", selection = { tagStatus = "tagged", tagPrefixList = ["v"], countType = "imageCountMoreThan", countNumber = 10 }, action = { type = "expire" } }
    ]
  })
}
