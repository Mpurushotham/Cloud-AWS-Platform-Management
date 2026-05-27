resource "aws_organizations_policy" "tag_policy" {
  name        = "cap-required-tags"
  description = "Enforce required resource tags across the organization"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Project = {
        tag_key = { "@@assign" = "Project" }
        tag_value = { "@@assign" = ["cap"] }
        enforced_for = { "@@assign" = ["ec2:instance", "s3:bucket", "rds:db", "eks:cluster", "ecs:cluster"] }
      }
      Environment = {
        tag_key = { "@@assign" = "Environment" }
        tag_value = { "@@assign" = ["dev", "staging", "prod", "sandbox", "shared", "security", "logging", "management"] }
        enforced_for = { "@@assign" = ["ec2:instance", "s3:bucket", "rds:db"] }
      }
      ManagedBy = {
        tag_key = { "@@assign" = "ManagedBy" }
        tag_value = { "@@assign" = ["terraform", "aws-cdk", "manual"] }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "tag_policy" {
  policy_id = aws_organizations_policy.tag_policy.id
  target_id = aws_organizations_organization.main.roots[0].id
}
