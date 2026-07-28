# Lab Profile — Free-Tier Deployable Platform

> **Navigation:** [Repo README](../../README.md) | [Lab Setup Runbook](../../docs/how-to/lab-setup-free-tier.md) | [Architecture Diagrams](../../docs/architecture/diagrams/) | [ADR Index](../../docs/adr/README.md)

A deployable, single-account version of this platform that runs at **$0/month**.

`terraform/environments/` describes the target state: eight accounts, EKS, RDS
Multi-AZ, Transit Gateway, OpenSearch, Shield Advanced. That is the right design
for production and costs roughly $400–600 per environment per month. It is not
something you can stand up on a free-tier account to learn from.

This directory is the same architecture with every billable component either
removed or placed behind a flag that defaults to off. What remains is the part
that teaches the most and costs the least: governance, identity, keyless CI/CD,
network topology, and a working request path.

## Layers

Apply in order. Each depends on outputs from the ones before it.

| Layer | Creates | Cost |
|-------|---------|------|
| [`00-identity`](00-identity/) | `cap-platform-admin` role, account password policy, S3 account PAB, default EBS encryption, IMDSv2 default | $0 |
| [`01-governance`](01-governance/) | 6 OUs, 7 SCPs, org CloudTrail, access-log bucket, budget alarm | $0 |
| [`02-bootstrap`](02-bootstrap/) | S3 state bucket, DynamoDB lock table, GitHub OIDC provider, 4 CI roles | $0 |
| [`03-network`](03-network/) | VPC, 6 subnets, gateway endpoints, security groups, NACLs, flow logs | $0 |
| [`04-workload`](04-workload/) | HTTP API, Lambda, DynamoDB, alarms, dashboard, SSM handoff | $0 |

## Quick start

```bash
# Layer 00 — identity
cd terraform/lab/00-identity
cp terraform.tfvars.example terraform.tfvars   # set break_glass_principal_arns
terraform init && terraform plan -var-file=terraform.tfvars -out=tfplan && terraform apply tfplan

# Layer 01 — governance (adopt the existing organization first)
cd ../01-governance
cp terraform.tfvars.example terraform.tfvars   # set budget_notification_emails
terraform init
terraform import aws_organizations_organization.this "$(aws organizations describe-organization --query 'Organization.Id' --output text)"
terraform plan -var-file=terraform.tfvars -out=tfplan && terraform apply tfplan

# Layer 02 — bootstrap
cd ../02-bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_org and access_log_bucket_name
terraform init && terraform plan -var-file=terraform.tfvars -out=tfplan && terraform apply tfplan

# Layer 03 — network
cd ../03-network
terraform init && terraform plan -out=tfplan && terraform apply tfplan

# Layer 04 — workload
cd ../04-workload
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan -var-file=terraform.tfvars -out=tfplan && terraform apply tfplan
terraform output -raw smoke_test | bash
```

Then confirm nothing billable was created:

```bash
../../scripts/lab-verify.sh
```

## If your CLI uses `aws login`

AWS CLI v2's browser sign-in stores its session under `~/.aws/login`, which the
Terraform AWS provider cannot read — it fails with "No valid credential sources
found". Export the session into the environment first:

```bash
eval "$(aws configure export-credentials --format env)"
```

These are short-lived credentials; re-run the command when they expire.

## What is deliberately switched off

Every one of these is written, validated and one variable away from working.
They are off because of what they cost, not because they are unfinished.

| Flag | Layer | Cost if enabled |
|------|-------|-----------------|
| `enable_nat_gateway` | 03-network | ~$32/month per AZ + data processing |
| `enable_interface_endpoints` | 03-network | ~$7.30/month per endpoint per AZ |
| `attach_to_vpc` | 04-workload | free, but needs one of the two above to function |
| `state_encryption = "aws:kms"` | 02-bootstrap | $1/month per key |

Not present at all, because no flag makes them cheap: EKS ($73/month per
cluster), RDS Multi-AZ, Transit Gateway, OpenSearch, Shield Advanced, AWS Config,
GuardDuty and Security Hub past their trial windows.

## Cost guardrails

Five independent limits, so that no single misconfiguration can produce a bill:

1. **Budget alarm** at 10% actual and 100% forecast of a $5 ceiling (layer 01)
2. **API Gateway throttling** — 5 req/s steady, 10 burst (layer 04)
3. **Lambda reserved concurrency** — 5 executions (layer 04)
4. **DynamoDB TTL** — records expire after 7 days (layer 04)
5. **CloudWatch alarm** on unexpected request volume (layer 04)

Plus `scripts/lab-verify.sh`, which fails if any billable resource appears.

## Teardown

```bash
./scripts/lab-teardown.sh
```

Removes layers 04 → 01 in reverse order. The state bucket and lock table carry
`prevent_destroy` and must be removed by hand if you really want them gone —
see the script's output for the exact commands.

## Relationship to `terraform/environments/`

The lab is not a fork of the environment code; it is a parallel, cost-bounded
implementation of the same design. Where the two differ, the reason is recorded
in an ADR:

- [ADR-0013](../../docs/adr/0013-single-account-lab-profile.md) — why a separate lab profile rather than variables on the production modules
- [ADR-0015](../../docs/adr/0015-lab-encryption-tradeoffs.md) — where the lab accepts weaker encryption and why
- [ADR-0016](../../docs/adr/0016-no-nat-gateway-in-lab.md) — what removing NAT costs you in capability
