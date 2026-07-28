# Service Control Policies

Policy documents consumed directly by Terraform, so what is reviewed in a pull
request is byte-for-byte what is enforced.

| File | Consumed by | Region list |
|------|-------------|-------------|
| `deny-root-user.json` | lab + organizations module | n/a |
| `deny-delete-cloudtrail.json` | lab + organizations module | n/a |
| `deny-disable-guardduty.json` | lab + organizations module | n/a |
| `deny-public-s3.json` | lab + organizations module | n/a |
| `require-encryption.json` | lab + organizations module | n/a |
| `require-mfa.json` | lab + organizations module | n/a |
| `deny-region-restriction.json` | `terraform/lab/01-governance` via `file()` | fixed in the document |
| `deny-region.json.tpl` | `terraform/modules/organizations` via `templatefile()` | injected from `var.allowed_regions` |

## Why the region policy exists twice

The two forms differ only in where the approved-region list comes from.

The lab layer keeps it **in the committed document**, so the policy under review
is exactly the policy applied and there is no variable to disagree with it. The
production module takes it as a **module input**, because different OUs there
may be confined to different regions.

The template carries no comments: `templatefile()` renders the file verbatim and
IAM rejects JSON containing `//`.

**Keep the two in step.** Changing the approved regions means editing both.

## Constraints

- 5120 bytes per policy after whitespace removal. Asserted by a Terraform
  precondition in `terraform/lab/01-governance/service-control-policies.tf`.
- Maximum 5 SCPs per target, and AWS-managed `FullAWSAccess` occupies one.
- **The Organizations management account is exempt from every SCP.** See
  [ADR-0006](../../docs/adr/0006-scps-as-preventive-guardrails.md).
