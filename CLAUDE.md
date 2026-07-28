# CLAUDE.md — Cloud-AWS-Platform-Management

## Project Overview

Production-grade multi-account AWS platform using Terraform (foundation layer) + CDK TypeScript (application layer) + GitHub Actions (CI/CD). Naming convention: `cap-{environment}-{component}`.

## Two Profiles — Know Which One You Are In

| | `terraform/environments/` | `terraform/lab/` |
|---|---|---|
| Target | 8-account Organization, EKS, RDS, TGW | Single account, Lambda only |
| Cost | ~$400–600/month per environment | **$0/month** |
| Status | Reference design | Deployed to account <ACCOUNT_ID> |

**The lab is budgeted at $0 and that is enforced.** Any billable resource added under `terraform/lab/` must sit behind a `count`/`for_each` guard whose variable defaults to `false`, with the cost recorded in an ADR. `scripts/check-billable-guards.py` fails the build otherwise, and `scripts/lab-verify.sh` fails if anything billable is actually running.

Never "fix" the lab by enabling NAT gateways, EKS, RDS or customer-managed KMS keys without being asked — those omissions are decisions, recorded in ADR-0013, 0015 and 0016.

## Lab Bootstrap Order

Apply in order; each layer consumes outputs from the previous one:

1. `terraform/lab/00-identity/` — `cap-platform-admin` role, account baseline
2. `terraform/lab/01-governance/` — OUs, SCPs, CloudTrail, budgets (**import the org first**)
3. `terraform/lab/02-bootstrap/` — state backend, GitHub OIDC, 4 CI roles
4. `terraform/lab/03-network/` — VPC, subnets, gateway endpoints, flow logs
5. `terraform/lab/04-workload/` — Lambda, API Gateway, DynamoDB, SSM handoff

Runbook: `docs/how-to/lab-setup-free-tier.md`.

**Credentials:** if `terraform plan` reports "No valid credential sources found" while the AWS CLI works, the session came from `aws login`, which the Terraform provider cannot read. Run `eval "$(aws configure export-credentials --format env)"`.

## Production Bootstrap Order (CRITICAL)

Must be run in this exact order — each step depends on resources from the previous:

1. `terraform/bootstrap/` — creates S3 state bucket in logging account, DynamoDB lock table, GitHub OIDC IdP, four IAM roles. **Run manually with temporary AdministratorAccess.**
2. After bootstrap apply: `terraform init -migrate-state` to move state to S3.
3. `terraform/environments/management/` — AWS Organization, all OUs, SCPs, member accounts.
4. `terraform/environments/logging/` — CloudTrail org trail, Config aggregator, audit S3 bucket.
5. `terraform/environments/security/` — Security Hub (aggregator), GuardDuty (master), IAM Identity Center.
6. `terraform/environments/shared-services/` — ECR, Route53, ACM, Transit Gateway, RAM shares.
7. `terraform/environments/{dev,staging,prod}/` — VPC, EKS, ECS, RDS, ElastiCache per environment.
8. `cdk/` — CDK stacks deploy in order: Network → Security → Platform → Data → API → Observability.

## GitHub OIDC Roles (created in bootstrap)

| Role Name | Trust | Used By |
|-----------|-------|---------|
| `cap-plan` | Any branch, PR | `07-terraform-plan.yml` |
| `cap-apply` | `refs/heads/main` only | `08-terraform-apply.yml` |
| `cap-image-push` | `refs/heads/main` only | `04-container-security.yml` |
| `cap-prowler` | Any branch | `06-compliance.yml` |

## Terraform Conventions

- **Backend**: S3 bucket in logging account + DynamoDB lock per environment.
- **Modules**: Each module has `main.tf` (minimal/comment), purpose-named files (`networking.tf`, `subnets.tf`, `rules.tf`), `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`.
- **Providers**: Always pin `aws ~> 5.0`, `terraform ~> 1.9`. Never use `latest`.
- **State keys**: `{layer}/terraform.tfstate` (e.g., `management/terraform.tfstate`, `dev/terraform.tfstate`).
- **Tags**: Apply via `local.common_tags` in every module. Required: `Project`, `Environment`, `ManagedBy`, `CostCenter`, `Owner`.
- **No inline SG rules**: Always use `aws_security_group_rule` resources, never inline `ingress`/`egress` blocks.
- **KMS**: Every service gets its own key per environment. Key alias: `alias/cap/{env}/kms/{service}`.

## CDK Conventions

- **Language**: TypeScript with `strict: true`.
- **Stack order** (enforce via `addDependency`): NetworkStack → SecurityStack → PlatformStack → DataStack → ApiStack → ObservabilityStack.
- **Constructs**: All L3 constructs live in `cdk/lib/constructs/`. Stacks in `cdk/lib/stacks/`.
- **Removal policy**: `RETAIN` for prod KMS keys, S3 buckets. `DESTROY` for dev/staging non-critical resources.
- **Environment config**: Read from `cdk.json` context (`cdk.node.tryGetContext('environment')`).
- **Cross-stack**: Use SSM Parameter Store for Terraform → CDK handoff (Terraform writes VPC IDs to SSM; CDK reads them).

## Architecture Decisions

Sixteen ADRs in `docs/adr/`. Before changing anything architectural, check whether a record already covers it — `docs/architecture/diagrams/06-adr-decision-tree.md` maps a question to its record.

- Write a new ADR when a change encodes a decision a reasonable engineer might later undo without knowing why.
- Never edit an accepted **Decision** section. Supersede with a new ADR instead.
- Always fill in the negative consequences. An ADR with no downsides will not be believed.

## Diagrams

Mermaid inside markdown, under `docs/architecture/diagrams/`. No build step. Colour convention: green = deployed and verified, orange = partial or caveated, red = a real risk, dashed grey = written but switched off. **Do not show a control as deployed when it is not** — an over-optimistic diagram is worse than none.

## Security Requirements (Non-Negotiable)

- Zero long-lived IAM credentials. All CI/CD uses OIDC.
- All S3 buckets: block public access + KMS encryption + versioning + access logging.
- All RDS: Multi-AZ + KMS + automated backups (7 days dev, 35 days prod) + enhanced monitoring.
- All EKS: Private endpoint only in prod. KMS-encrypted secrets. IRSA for all service accounts.
- All EC2: IMDSv2 required (http_tokens = required). No key pairs — use SSM Session Manager.
- All KMS keys: `enable_key_rotation = true`. Prod keys: deletion window 30 days.

## Workflow Gates

| Environment | Terraform Apply Gate |
|-------------|---------------------|
| dev | Auto-approve on merge to main |
| staging | 1 reviewer approval |
| prod | 2 reviewer approvals + 60-minute wait |

## Common Commands

```bash
# Lab: verify nothing billable is running and all controls are present
./scripts/lab-verify.sh

# Lab: confirm billable resources are gated off by default
python3 scripts/check-billable-guards.py terraform/lab

# Lab: destroy in reverse order
./scripts/lab-teardown.sh

# Parse check across the whole tree (catches malformed HCL, not just formatting)
terraform fmt -check -recursive terraform/

# Pre-commit
pre-commit run --all-files

# Terraform (from environment directory)
terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform show -json tfplan | conftest test - --policy ../../conftest.rego

# CDK
cd cdk && npm test
npx cdk synth --all
npx cdk diff --all

# Drift detection (all environments)
./scripts/drift-detection.sh

# IaC scanning
checkov -d terraform/ --config-file .checkov.yml
tfsec terraform/ --exclude-downloaded-modules
```

## Directory Owners

| Path | Owner Team |
|------|-----------|
| `terraform/` | platform-team |
| `security/` | security-team |
| `kubernetes/` | platform-team |
| `cdk/` | platform-team |
| `.github/workflows/` | platform-team |
| `idp/` | platform-team |
| `docs/` | platform-team |
