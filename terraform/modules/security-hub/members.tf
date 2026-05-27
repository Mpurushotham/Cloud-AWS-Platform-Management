resource "aws_securityhub_member" "members" {
  for_each = toset(var.member_account_ids)

  account_id = each.value
  invite     = true
  depends_on = [aws_securityhub_account.main]
}
