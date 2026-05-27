# Account Vending Runbook

## Overview

New accounts are provisioned using `scripts/account-vending.py`, which:
1. Creates an AWS Organizations member account
2. Moves it to the correct OU
3. Triggers Control Tower Account Factory enrollment

## Prerequisites

- Temporary credentials in the management account with OrganizationsFullAccess
- Account name must follow pattern: `cap-{team}-{purpose}` (e.g., `cap-team-a-dev`)
- Email must be a unique address not already associated with an AWS account

## Steps

### 1. Provision the Account

```bash
python3 scripts/account-vending.py \
  --name "cap-team-a-dev" \
  --email "aws-team-a-dev@example.com" \
  --ou "Non-Prod" \
  --environment dev
```

### 2. Apply Landing Zone Baseline

```bash
cd terraform/environments/dev
# Add new account to variables and apply
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 3. Assign SSO Access

In IAM Identity Center, assign the following permission sets:
- `Developer` → team members
- `ReadOnly` → stakeholders
- `PlatformAdmin` → platform team (break-glass only)

### 4. Verify

- [ ] Account appears in AWS Organizations
- [ ] GuardDuty member enrolled (Security Hub → Accounts)
- [ ] Config recorder active (Config → Recorders)
- [ ] CloudTrail delivering logs (CloudTrail → Trails)
- [ ] SSO access working (test login)
- [ ] VPC deployed with correct CIDR allocation

## CIDR Allocation

| Environment | CIDR |
|-------------|------|
| dev | 10.10.0.0/16 |
| test | 10.11.0.0/16 |
| staging | 10.20.0.0/16 |
| prod | 10.30.0.0/16 |
| sandbox | 10.90.0.0/16 |
| shared-services | 10.0.0.0/16 |
