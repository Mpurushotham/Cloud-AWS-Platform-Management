# CLAUDE.md — Cloud-AWS-Platform-Management

## Project Overview

Production-grade multi-account AWS platform using Terraform (foundation layer) + CDK TypeScript (application layer) + GitHub Actions (CI/CD). Naming convention: `cap-{environment}-{component}`.

## Bootstrap Order (CRITICAL)

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
