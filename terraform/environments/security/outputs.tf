output "security_hub_arn" { value = module.security_hub.hub_arn }
output "guardduty_detector_id" { value = module.guardduty.detector_id }
output "kms_key_arns" { value = module.kms.key_arns }
