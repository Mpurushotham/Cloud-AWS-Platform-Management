# OU tree. Mirrors the target multi-account topology exactly, so that moving
# from the single-account lab to real member accounts is an account-creation
# exercise rather than a redesign.
#
#   Root
#   ├── Core            — security, logging, landing zone
#   ├── Infrastructure  — shared services
#   ├── Workloads
#   │   ├── Non-Prod    — dev, test, staging
#   │   └── Prod        — production only
#   └── Sandbox         — time-boxed experimentation

locals {
  root_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "core" {
  name      = "Core"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "non_prod" {
  name      = "Non-Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = local.root_id
}
