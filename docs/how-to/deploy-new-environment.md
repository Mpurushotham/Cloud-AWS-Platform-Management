# How to Deploy a New Workload Environment

## When to Use This Guide

Use this guide when:
- Adding a **new environment** (e.g., `perf`, `uat`, `sandbox`) alongside existing dev/staging/prod
- Provisioning a **new team's isolated AWS account** within an existing OU
- Cloning an existing environment to a different AWS region

Do **not** use this guide to bootstrap the platform from scratch — see [bootstrap-platform.md](bootstrap-platform.md).

---

## Decision: New Account vs New Namespace

| Scenario | Recommendation |
|----------|---------------|
| Different team or business unit | New AWS account (isolation boundary) |
| Same team, extra SDLC stage (e.g., perf) | New account within Workloads OU |
| Logical separation only (e.g., feature branch testing) | Kubernetes namespace in existing dev account |
| Cost center separation required | New AWS account (separate billing) |

---

## Step 1 — Provision the AWS Account

Use the account vending script:

```bash
python3 scripts/account-vending.py \
  --name "cap-team-a-uat" \
  --email "aws-cap-team-a-uat@your-org.com" \
  --ou "Non-Prod" \
  --environment uat
```

The script creates the account and moves it to the correct OU. Wait for `CREATE_SUCCEEDED` (typically 2–5 minutes).

Verify:
```bash
aws organizations list-accounts \
  --query 'Accounts[?Name==`cap-team-a-uat`]'
```

---

## Step 2 — Create the Terraform Environment Root

Copy an existing environment root and update values:

```bash
cp -r terraform/environments/dev terraform/environments/uat
cd terraform/environments/uat
```

Update `backend.tf` — change the state key:
```hcl
key = "uat/terraform.tfstate"
```

Update `variables.tf` — set the new account ID and CIDR:
```hcl
variable "account_id"  { default = "NEW_ACCOUNT_ID" }
variable "vpc_cidr"    { default = "10.40.0.0/16" }   # pick unused CIDR block
variable "environment" { default = "uat" }
```

Update `terraform.tfvars.example` and create `terraform.tfvars` with real values.

---

## Step 3 — Add GitHub Actions Matrix Entry

In `.github/workflows/07-terraform-plan.yml` and `08-terraform-apply.yml`, add `uat` to the environment matrix:

```yaml
# 07-terraform-plan.yml
strategy:
  matrix:
    environment: [dev, staging, uat, prod]   # add uat

# 08-terraform-apply.yml — add uat between staging and prod
uat:
  needs: [staging]
  environment: uat          # create this GitHub environment first
  ...
```

Create the GitHub Actions environment in the repo settings:
```bash
gh api repos/Mpurushotham/Cloud-AWS-Platform-Management/environments \
  -f name=uat -f wait_timer=0
```

---

## Step 4 — Configure OIDC Role Trust

The `cap-apply` role's trust policy must allow the new environment's workflow:

```bash
# In terraform/bootstrap/oidc.tf, the trust already allows refs/heads/main
# No change needed if using the main branch workflow
# If you need environment-specific assume-role, add to the condition:
```

For cross-account assume-role, the management account's `cap-apply` role needs permission to assume a role in the new account. Add to `terraform/bootstrap/oidc.tf`:

```hcl
# In the cap-apply role's inline policy, add the new account:
"arn:aws:iam::NEW_ACCOUNT_ID:role/OrganizationAccountAccessRole"
```

---

## Step 5 — Apply the New Environment

Trigger the apply workflow manually for the new environment only:

```bash
gh workflow run 08-terraform-apply.yml \
  -f environment=uat \
  -f auto_approve=false
```

Or merge a PR — the matrix will run plan for all environments, and apply for `uat` will require reviewer approval (based on the environment protection rules you set in step 3).

---

## Step 6 — Enroll in Security Services

After the account exists, enroll it in org-wide security services:

```bash
# GuardDuty — run from security account
aws guardduty create-members \
  --detector-id DETECTOR_ID \
  --account-details AccountId=NEW_ACCOUNT_ID,Email=aws-cap-team-a-uat@your-org.com

# Security Hub — accept invitation from new account
aws securityhub accept-administrator-invitation \
  --administrator-id SECURITY_ACCOUNT_ID \
  --invitation-id INVITATION_ID

# Config — recorder starts automatically via Terraform landing zone
```

---

## Step 7 — Assign IAM Identity Center Access

```bash
# In IAM Identity Center console or via Terraform:
# security account → IAM Identity Center → AWS Accounts → Assign users and groups
# Assign: Developer permission set to the team, ReadOnly to stakeholders
```

---

## Verification Checklist

- [ ] Account appears in AWS Organizations with correct OU
- [ ] CIDR does not overlap with any existing VPC (check [CIDR table](../runbooks/account-vending.md#cidr-allocation))
- [ ] Terraform state key is unique (`uat/terraform.tfstate`)
- [ ] GuardDuty member status: `Enabled`
- [ ] Security Hub member status: `Enabled`
- [ ] Config recorder active
- [ ] CloudTrail delivering to central S3 bucket
- [ ] KMS keys created (11 service keys for `uat` environment)
- [ ] EKS cluster nodes in `Ready` state
- [ ] SSO access verified by a team member

---

## CIDR Allocation Reference

| Environment | CIDR Block | Account |
|-------------|-----------|---------|
| shared-services | 10.0.0.0/16 | Shared Services |
| dev | 10.10.0.0/16 | Dev Account |
| test | 10.11.0.0/16 | Test Account |
| staging | 10.20.0.0/16 | Staging Account |
| prod | 10.30.0.0/16 | Prod Account |
| uat | 10.40.0.0/16 | UAT Account |
| perf | 10.50.0.0/16 | Perf Account |
| sandbox | 10.90.0.0/16 | Sandbox Account |

Always pick the next unused `/16` block. Overlapping CIDRs will break Transit Gateway routing.
