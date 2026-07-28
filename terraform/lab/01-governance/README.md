# Lab Layer 01 — Governance

> **Navigation:** [Lab README](../README.md) | [Org Topology Diagram](../../../docs/architecture/diagrams/01-organization-topology.md) | [How to Manage SCPs](../../../docs/how-to/manage-scps.md) | [ADR-0006 SCPs as Guardrails](../../../docs/adr/0006-scps-as-preventive-guardrails.md)

Establishes the organizational structure, preventive guardrails, audit trail and
cost guardrail. Depends on [layer 00](../00-identity/README.md).

## What it creates

| Resource | Purpose | Cost |
|----------|---------|------|
| 6 Organizational Units | Core, Infrastructure, Workloads (Non-Prod, Prod), Sandbox | $0 |
| 7 Service Control Policies | Preventive guardrails from `security/scps/` | $0 |
| CloudTrail organization trail | Multi-region management events, log file validation | $0 (first trail) |
| S3 trail bucket | Versioned, SSE-S3, TLS-only, 30-day expiry | ~$0 (well under 5 GB free tier) |
| Monthly budget | Alerts at 10% actual and 100% forecast | $0 (2 budgets free per account) |

## The organization is imported, not created

The AWS Organization already existed. Adopt it before the first apply:

```bash
cd terraform/lab/01-governance
terraform init

ORG_ID="$(aws organizations describe-organization --query 'Organization.Id' --output text)"
terraform import aws_organizations_organization.this "$ORG_ID"
```

Then plan and apply as usual:

```bash
cp terraform.tfvars.example terraform.tfvars   # set budget_notification_emails
terraform plan  -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

## SCP attachment map

| SCP | Attached to | Effect |
|-----|-------------|--------|
| `deny-root-user` | Root | Block all root-user API activity |
| `deny-delete-cloudtrail` | Root | Prevent audit trail tampering |
| `deny-public-s3` | Root | Prevent public buckets and ACLs |
| `deny-disable-guardduty` | Root | Prevent threat detection shutdown |
| `require-encryption` | Workloads OU | Require encryption for S3, EBS, RDS |
| `deny-region-restriction` | Workloads OU | Confine workloads to approved regions |
| `require-mfa` | Prod OU | Require MFA for non-automation calls |

## Two limitations you must understand

**1. SCPs do not restrict the management account.** AWS exempts the Organizations
management account from every SCP, without exception. In this single-account lab
*all* resources live in the management account, so the attachments above are
structurally correct and reviewable, but they enforce nothing today. They begin
enforcing the moment real member accounts are created and moved into the OUs.
This is a property of AWS, not a shortcut taken here — see
[ADR-0013](../../../docs/adr/0013-single-account-lab-profile.md).

**2. `require-encryption` is a known footgun.** Its `DenyUnencryptedS3Uploads`
statement denies any `s3:PutObject` whose request lacks an explicit
`x-amz-server-side-encryption: aws:kms` header. Bucket *default* encryption does
not set that header, so services that write with default encryption — including
CloudTrail, Config, ELB access logs and VPC flow logs — are denied. It is
attached to the Workloads OU only, and the trail bucket in this layer therefore
sits outside its scope. Before attaching it anywhere new, confirm every writer
sends the header explicitly.

## Root SCP quota

A target accepts at most **5** SCPs, and AWS-managed `FullAWSAccess` occupies one.
The four root attachments above put the root exactly at quota. Adding a fifth
root-level guardrail requires merging its statements into an existing policy
rather than attaching a new one.

## Verification

```bash
aws organizations list-roots --query 'Roots[0].PolicyTypes'
aws organizations list-organizational-units-for-parent --parent-id "$(terraform output -raw root_id)"
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[?starts_with(Name,`cap-`)].Name'
aws cloudtrail get-trail-status --name cap-lab-org-trail --query 'IsLogging'
aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --query 'Budgets[].BudgetName'
```
