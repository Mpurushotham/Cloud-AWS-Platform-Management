resource "aws_iam_policy" "deny_imdsv1" {
  name        = "cap-deny-imdsv1"
  description = "Deny launching EC2 instances with IMDSv1 (http_tokens != required)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "ec2:RunInstances"
      Resource = "arn:aws:ec2:*:*:instance/*"
      Condition = {
        StringNotEquals = { "ec2:MetadataHttpTokens" = "required" }
      }
    }]
  })
}

resource "aws_iam_policy" "deny_public_s3" {
  name        = "cap-deny-public-s3-access"
  description = "Deny S3 operations that remove public access blocks"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "s3:PutBucketPublicAccessBlock"
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "s3:x-amz-block-public-acls"      = "true"
          "s3:x-amz-block-public-policy"    = "true"
          "s3:x-amz-ignore-public-acls"     = "true"
          "s3:x-amz-restrict-public-buckets" = "true"
        }
      }
    }]
  })
}
