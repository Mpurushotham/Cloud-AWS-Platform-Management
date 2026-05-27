resource "aws_guardduty_publishing_destination" "s3" {
  detector_id     = aws_guardduty_detector.main.id
  destination_arn = var.finding_s3_bucket_arn
  kms_key_arn     = var.kms_key_arn
  destination_type = "S3"
}
