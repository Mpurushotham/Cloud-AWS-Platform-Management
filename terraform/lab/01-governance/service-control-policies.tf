# SCP definitions and attachments.
#
# Policy documents are read from security/scps/ rather than redefined here, so
# that what is reviewed in a pull request is exactly what is enforced.

resource "aws_organizations_policy" "scp" {
  for_each = var.attach_scps ? local.scps : {}

  name        = "cap-${each.key}"
  description = each.value
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.scp_dir}/${each.key}.json")

  # SCP documents have a hard 5120-byte limit after whitespace removal.
  lifecycle {
    precondition {
      condition     = length(file("${local.scp_dir}/${each.key}.json")) <= 5120
      error_message = "SCP ${each.key}.json exceeds the 5120-byte AWS limit."
    }
  }
}

resource "aws_organizations_policy_attachment" "scp" {
  for_each = var.attach_scps ? local.scp_attachments : {}

  policy_id = aws_organizations_policy.scp[each.key].id
  target_id = each.value
}
