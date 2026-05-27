output "detector_id" { value = aws_guardduty_detector.main.id }
output "master_account_id" { value = data.aws_caller_identity.current.account_id }
data "aws_caller_identity" "current" {}
