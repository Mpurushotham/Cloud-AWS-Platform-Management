# How to Bootstrap the Platform from Scratch

## When to Use This Guide

Use this guide when:
- Standing up the platform in a **brand-new AWS Organization**
- Rebuilding after a catastrophic management account failure
- Provisioning a parallel organization for a new business unit

Do **not** use this guide to add a new workload account — see [deploy-new-environment.md](deploy-new-environment.md).

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| AWS Management Account | Root user access for initial Organization creation |
| GitHub Organization | Admin access to create repos and configure OIDC |
| Tools installed | `terraform >= 1.9`, `aws-cli >= 2.x`, `gh`, `jq`, `node >= 20` |
| Domain/email aliases | One unique email per AWS account (use `+` addressing) |

Run the bootstrap script to install all tools:
```bash
./scripts/bootstrap.sh
```

---

## Phase 1: Manual Pre-Bootstrap (Run Once, As Root)

These steps must be run manually. They cannot be automated until OIDC exists.

### Step 1 — Enable AWS Organizations

```bash
aws organizations create-organization --feature-set ALL
# Save the organization ID (o-xxxxxxxxxxxx)
```

### Step 2 — Enable required AWS service access

```bash
# These allow Control Tower, Config, and Security Hub to work org-wide
for SERVICE in \
  cloudtrail.amazonaws.com \
  config.amazonaws.com \
  ram.amazonaws.com \
  sso.amazonaws.com \
  guardduty.amazonaws.com \
  securityhub.amazonaws.com \
  access-analyzer.amazonaws.com \
  controltower.amazonaws.com; do
  aws organizations enable-aws-service-access --service-principal $SERVICE
done
```

### Step 3 — Bootstrap Terraform state + OIDC

```bash
cd terraform/bootstrap

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit: org_id, management_account_id, github_org, allowed_regions

terraform init   # uses local state at this point
terraform plan -var-file=terraform.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

This creates:
- S3 state bucket with KMS encryption
- DynamoDB lock table
- GitHub OIDC identity provider
- Four IAM roles: `cap-plan`, `cap-apply`, `cap-image-push`, `cap-prowler`

### Step 4 — Migrate state to S3

```bash
# Uncomment the S3 backend block in backend.tf, then:
terraform init -migrate-state
# Confirm 'yes' when prompted
```

---

## Phase 2: Organization Foundation (via GitHub Actions)

All subsequent steps run through the `platform-foundation.yml` workflow. Trigger manually:

```
GitHub → Actions → platform-foundation → Run workflow → layer: management
```

### Step 5 — Management layer (Organization + SCPs + OUs)

The workflow runs:
```bash
cd terraform/environments/management
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -auto-approve  # (dev only; prod requires reviewers)
```

Verify:
```bash
aws organizations list-accounts --query 'Accounts[].{Name:Name,Status:Status}' --output table
aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,Id:Id}' --output table
```

### Step 6 — Logging layer (CloudTrail + Config + Audit S3)

```
platform-foundation → Run workflow → layer: logging
```

Verify CloudTrail is delivering:
```bash
aws cloudtrail get-trail-status --name cap-org-trail \
  --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}'
```

### Step 7 — Security layer (Security Hub + GuardDuty + IAM Identity Center)

```
platform-foundation → Run workflow → layer: security
```

Verify:
```bash
# Security Hub standards active
aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].StandardsArn'

# GuardDuty enabled in all regions
aws guardduty list-detectors
```

### Step 8 — Shared Services layer (ECR + Route53 + Transit Gateway)

```
platform-foundation → Run workflow → layer: shared-services
```

---

## Phase 3: Workload Environments

Trigger `08-terraform-apply.yml` for each environment in order:

```
dev → staging → prod
```

Each apply creates: VPC (3-tier, 3 AZs), EKS cluster, ECS cluster, RDS, ElastiCache, WAF, KMS keys.

```bash
# Verify VPC created correctly
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=dev" \
  --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,State:State}'
```

---

## Phase 4: CDK Application Layer

```bash
cd cdk
npm ci
npm test              # must pass before deploy

npx cdk deploy --all --context environment=dev --require-approval never
npx cdk deploy --all --context environment=staging
npx cdk deploy --all --context environment=prod  # prompts for each stack
```

CDK deploys in dependency order: NetworkStack → SecurityStack → PlatformStack → DataStack → ApiStack → ObservabilityStack.

---

## Post-Bootstrap Verification Checklist

```bash
# Run full pre-commit scan
pre-commit run --all-files

# Check Terraform drift (all environments)
./scripts/drift-detection.sh

# Run Prowler compliance scan
# (triggers automatically via 06-compliance.yml on schedule)
gh workflow run 06-compliance.yml
```

- [ ] All 7 SCPs attached and active
- [ ] GuardDuty members enrolled in security account
- [ ] Security Hub findings aggregated from all regions
- [ ] CloudTrail delivering to centralized S3 bucket
- [ ] IAM Identity Center users can log in
- [ ] EKS nodes in Ready state
- [ ] RDS instances in Available state
- [ ] KMS key rotation enabled for all 11 service keys
- [ ] No CRITICAL findings in Security Hub

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| OIDC `403 Forbidden` | Wrong branch in trust policy | Verify `cap-apply` trust allows `refs/heads/main` |
| State lock timeout | Previous apply crashed | `terraform force-unlock LOCK_ID` |
| SCP blocking apply | Role not in exemption list | Check `ArnNotLike` condition in SCP JSON |
| EKS nodes not joining | IMDSv2 not configured | Verify launch template `http_tokens=required` |
| GuardDuty member enroll fails | Delegated admin not set | Run management account setup first |
