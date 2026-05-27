variable "environment" { description = "Environment name"; type = string }
variable "member_account_ids" { description = "Member account IDs to enroll"; type = list(string); default = [] }
variable "enable_cis" { description = "Enable CIS AWS Foundations standard"; type = bool; default = true }
variable "enable_pci" { description = "Enable PCI-DSS standard"; type = bool; default = false }
variable "enable_nist" { description = "Enable NIST 800-53 standard"; type = bool; default = false }
variable "sns_endpoint" { description = "HTTPS endpoint for security finding notifications"; type = string; default = "" }
