resource "aws_guardduty_member" "members" {
  for_each = var.member_account_emails

  account_id                 = each.key
  email                      = each.value
  detector_id                = aws_guardduty_detector.main.id
  invite                     = true
  disable_email_notification = true
}
