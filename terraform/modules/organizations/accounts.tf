locals {
  ou_id_map = {
    core           = aws_organizations_organizational_unit.core.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    "non-prod"     = aws_organizations_organizational_unit.non_prod.id
    prod           = aws_organizations_organizational_unit.prod.id
    sandbox        = aws_organizations_organizational_unit.sandbox.id
  }
}

resource "aws_organizations_account" "accounts" {
  for_each = var.member_accounts

  name      = each.key
  email     = each.value.email
  parent_id = local.ou_id_map[each.value.parent_ou]

  role_name                  = "AWSControlTowerExecution"
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
    prevent_destroy = true
  }
}
