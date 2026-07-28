resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

# Without this, GuardDuty is enabled only in the account that ran the apply.
# auto_enable_organization_members ensures accounts joining the organization
# later are covered on creation rather than whenever somebody notices.
resource "aws_guardduty_organization_configuration" "main" {
  count = var.is_organization_admin ? 1 : 0

  detector_id                      = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"
}
