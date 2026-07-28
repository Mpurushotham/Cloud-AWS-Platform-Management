# How to Set Up the Free-Tier Lab

> **Navigation:** [Docs Index](../README.md) | [Lab README](../../terraform/lab/README.md) | [Bootstrap Sequence Diagram](../architecture/diagrams/07-bootstrap-sequence.md) | [ADR-0013](../adr/0013-single-account-lab-profile.md)

End-to-end runbook for deploying the platform into a single AWS account at
**$0/month**. This is the procedure that was actually executed against account
`<ACCOUNT_ID>`; the verification output at each step is what it produced.

**Time:** about 45 minutes, most of it waiting for S3 lifecycle configuration.

---

## Prerequisites

| Requirement | Check |
|-------------|-------|
| AWS account with Organizations enabled | `aws organizations describe-organization` |
| Terraform ~> 1.9 | `terraform version` |
| AWS CLI v2 | `aws --version` |
| An IAM user (not just root) | `aws iam list-users` |
| MFA on that user | `aws iam list-mfa-devices --user-name <user>` |

If Organizations is not enabled, create it first — it is free:

```bash
aws organizations create-organization --feature-set ALL
```

---

## Step 0 — Credentials

The Terraform AWS provider cannot read the session that AWS CLI v2's
`aws login` stores under `~/.aws/login`. If `terraform plan` fails with
**"No valid credential sources found"** while `aws sts get-caller-identity`
works, this is why:

```bash
eval "$(aws configure export-credentials --format env)"
```

These credentials are short-lived. Re-run when they expire.

---

## Step 1 — Identity

Creates the MFA-gated admin role and the account security baseline.

```bash
cd terraform/lab/00-identity
cp terraform.tfvars.example terraform.tfvars

aws iam list-users --query 'Users[].Arn' --output text   # put yours in the tfvars

terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Creates 7 resources: the role, its guardrail policy, the AdministratorAccess
attachment, the password policy, the account S3 public access block, default EBS
encryption and the IMDSv2 region default.

**Then switch off root.** Follow the cutover procedure in
[`00-identity/README.md`](../../terraform/lab/00-identity/README.md) — it verifies
the replacement identity works *before* root is retired. Do not skip the
verification step.

---

## Step 2 — Governance

The organization already exists, so adopt it rather than creating it:

```bash
cd ../01-governance
cp terraform.tfvars.example terraform.tfvars   # set budget_notification_emails

terraform init
terraform import aws_organizations_organization.this \
  "$(aws organizations describe-organization --query 'Organization.Id' --output text)"

terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Creates 35 resources: 6 OUs, 7 SCPs and their attachments, the organization
CloudTrail with its bucket, the central access-log bucket, and the budget.

```bash
aws organizations list-roots --query 'Roots[0].PolicyTypes'
aws cloudtrail get-trail-status --name cap-lab-org-trail --query 'IsLogging'
```

> **What this does not do:** the management account is exempt from all SCPs, so
> the seven policies are attached and correct but enforce nothing until member
> accounts exist. See [ADR-0013](../adr/0013-single-account-lab-profile.md).

---

## Step 3 — Bootstrap

```bash
cd ../02-bootstrap
cp terraform.tfvars.example terraform.tfvars

# github_org, and the access-log bucket from the previous layer:
terraform -chdir=../01-governance output -raw access_logs_bucket_name

terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Creates 22 resources: the state bucket, the lock table, the GitHub OIDC provider
and the four CI roles.

Register the roles with GitHub:

```bash
terraform output -raw github_cli_commands | bash
```

Optionally migrate this layer's state into the bucket it just created:

```bash
terraform output -raw backend_config   # set key = "lab/bootstrap/terraform.tfstate"
# write backend.tf, then:
terraform init -migrate-state
```

---

## Step 4 — Network

```bash
cd ../03-network
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Creates 43 resources: the VPC, 6 subnets across 2 AZs, route tables, both
gateway endpoints, 4 security groups with 8 rules, a NACL and flow logs.

```bash
# There should be no NAT gateway and no Elastic IP
aws ec2 describe-nat-gateways --query 'NatGateways[?State!=`deleted`]'
aws ec2 describe-addresses    --query 'Addresses'
```

---

## Step 5 — Workload

```bash
cd ../04-workload
cp terraform.tfvars.example terraform.tfvars   # set alarm_email
terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Creates 29 resources: the DynamoDB table, the Lambda function and its role, the
HTTP API with 3 routes, 2 log groups, 4 alarms, a dashboard, the SNS topic and 8
SSM parameters.

Prove the request path works:

```bash
terraform output -raw smoke_test | bash
```

Expected:

```json
{"status": "ok", "environment": "lab"}
{"pk": "…", "name": "first", "created_at": 1785…, "expires_at": 1785…}
{"items": [...], "count": 1}
```

---

## Step 6 — Verify

```bash
cd ../../..
./scripts/lab-verify.sh
```

This is the check that matters. It fails if any billable resource exists and if
any expected control is missing:

```
Billable resources (all must be empty)
  ok    NAT gateways: none
  ok    Elastic IPs: none
  ok    Interface VPC endpoints: none
  ok    EC2 instances: none
  ok    RDS instances: none
  ok    EKS clusters: none
  …
Result
PASSED — lab is intact and nothing billable is running.
```

---

## What now exists

| Layer | Resources | Monthly cost |
|-------|-----------|--------------|
| 00 identity | 7 | $0 |
| 01 governance | 35 | $0 |
| 02 bootstrap | 22 | $0 |
| 03 network | 43 | $0 |
| 04 workload | 29 | $0 |
| **Total** | **136** | **$0** |

---

## Problems you are likely to hit

**"No valid credential sources found"** — see Step 0.

**"DBSubnetGroupDescription must not contain non-printable control characters"** —
the RDS API rejects non-ASCII. An em dash in a description will do it. Use plain
ASCII in RDS descriptions.

**`GET /items` returns 500 while `POST /items` works** — DynamoDB returns numbers
as `decimal.Decimal`, which `json.dumps` cannot serialise. Items written in the
same process are plain ints, so only the read path fails. Fixed in
`04-workload/src/handler.py` with a `default=` serialiser; the same bug will
appear in any handler that returns DynamoDB output directly.

**Terraform refuses to destroy the state bucket** — intended. `prevent_destroy`
protects the state bucket, the lock table and the organization. See
`scripts/lab-teardown.sh` for the manual commands.

**An SCP change appears to do nothing** — it probably is doing nothing. The
management account is exempt.

---

## Teardown

```bash
./scripts/lab-teardown.sh
```

Destroys layers 04 → 00 in reverse order after confirming the account ID. The
state bucket, lock table and organization survive by design; the script prints
the manual commands for those.

---

## Where to go next

The single highest-value change is **creating real member accounts**. It is what
makes the SCP layer genuinely enforcing and removes the largest gap between this
lab and the target architecture. Everything else — NAT gateways, EKS,
customer-managed KMS keys — is a cost decision that can be reversed with a
variable.

- [ADR-0013](../adr/0013-single-account-lab-profile.md) — what the lab cannot validate
- [Known issues](../security/known-issues.md) — what is still outstanding
- [Security best practices](../security/security-best-practices.md) — what is enforced and what is not
