# nosemgrep: aws-dynamodb-table-unencrypted -- encrypted with an AWS-owned key.
# A customer-managed key costs $1/month against a $0 budget; recorded in
# docs/adr/0015-lab-encryption-tradeoffs.md.
resource "aws_dynamodb_table" "items" {
  name = local.table_name

  # On-demand rather than provisioned: an idle lab table then costs nothing at
  # all, and there is no capacity to tune or forget about.
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # Records self-delete after seven days, so the table cannot silently grow out
  # of the free tier. TTL deletions are not billed.
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  # Encryption is on by default with an AWS-owned key at no charge. A
  # customer-managed key would cost $1/month; production should pay that to get
  # an auditable key policy and independent rotation. See ADR-0015.
  server_side_encryption {
    enabled = false
  }

  tags = { Name = local.table_name }
}
