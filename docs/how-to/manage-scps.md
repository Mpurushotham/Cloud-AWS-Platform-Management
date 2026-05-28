# How to Manage Service Control Policies (SCPs)

## When to Use This Guide

Use this guide when:
- Adding a new preventative guardrail across the organization
- Troubleshooting an `AccessDenied` error caused by an SCP
- Modifying an existing SCP to add an exemption role
- Understanding which SCP applies to which OU

---

## SCP Architecture

SCPs are **preventative** controls — they restrict the maximum permissions an IAM entity can have, regardless of what the IAM policy grants. They do not grant permissions.

```
Root (Management Account)
├── SCP: deny-root-user          ← applies to ALL accounts
├── SCP: deny-delete-cloudtrail  ← applies to ALL accounts
├── SCP: deny-disable-guardduty  ← applies to ALL accounts
├── SCP: deny-public-s3          ← applies to ALL accounts
│
├── Workloads OU
│   ├── SCP: require-encryption  ← dev, staging, prod
│   ├── SCP: deny-region-restriction
│   │
│   └── Prod OU
│       └── SCP: require-mfa     ← prod only
│
└── Sandbox OU
    └── SCP: deny-region-restriction (us-east-1 only)
```

---

## Step 1 — Understand the SCP You Need

Before writing an SCP, answer:
1. **What are you preventing?** (specific API actions)
2. **Which accounts/OUs?** (not all SCPs need to apply everywhere)
3. **Who needs an exemption?** (automation roles, Control Tower roles)
4. **Is this additive or replacing an existing SCP?**

Common SCP patterns:

| Goal | SCP Strategy |
|------|-------------|
| Block an action entirely | `Deny` + `Action` + `Resource: *` |
| Block unless specific role | `Deny` + `ArnNotLike` condition on `aws:PrincipalArn` |
| Block in specific region | `Deny` + `StringNotEquals aws:RequestedRegion` |
| Block without specific tag | `Deny` + `Null` or `StringNotEquals` on resource tag |

---

## Step 2 — Write the SCP JSON

Create a new file in `security/scps/`:

```bash
# Example: prevent creation of non-encrypted SNS topics
cat > security/scps/require-sns-encryption.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedSNS",
      "Effect": "Deny",
      "Action": "sns:CreateTopic",
      "Resource": "*",
      "Condition": {
        "Null": {
          "sns:KmsMasterKeyId": "true"
        },
        "ArnNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::*:role/AWSControlTowerExecution",
            "arn:aws:iam::*:role/cap-apply"
          ]
        }
      }
    }
  ]
}
EOF
```

**Always include exemptions for:**
- `arn:aws:iam::*:role/AWSControlTowerExecution` — Control Tower needs this
- `arn:aws:iam::*:role/cap-apply` — Terraform apply role
- Any other automation roles that legitimately need the action

---

## Step 3 — Register the SCP in Terraform

Add the new SCP to `terraform/modules/organizations/scps.tf`:

```hcl
# In the local.scps map, add:
locals {
  scps = {
    ...
    "require-sns-encryption" = {
      name        = "RequireSNSEncryption"
      description = "Deny creation of SNS topics without KMS encryption"
      target_id   = aws_organizations_organizational_unit.workloads.id
    }
  }
}
```

The module reads the JSON file automatically by convention:
```hcl
resource "aws_organizations_policy" "scp" {
  for_each = local.scps
  name     = each.value.name
  content  = file("${path.root}/../../../security/scps/${each.key}.json")
}
```

---

## Step 4 — Test the SCP in Sandbox First

**Never apply a new SCP directly to Prod OU.** Test in Sandbox first:

```bash
# Change target_id temporarily to sandbox OU for testing
# In scps.tf, set target_id = aws_organizations_organizational_unit.sandbox.id

cd terraform/environments/management
terraform plan -var-file=terraform.tfvars -out=tfplan

# Review: confirm only sandbox OU is targeted
terraform show tfplan | grep -A5 "require-sns-encryption"
```

Test that the SCP is working:
```bash
# From a sandbox account (non-exempt role):
aws sns create-topic --name test-unencrypted-topic
# Expected: AccessDenied

# From cap-apply role (exempt):
aws sns create-topic --name test-unencrypted-topic --kms-master-key-id alias/aws/sns
# Expected: success
```

---

## Step 5 — Promote to Target OU

After sandbox validation, update the `target_id` to the intended OU and open a PR.

The PR triggers `07-terraform-plan.yml` which will show the SCP change in the plan output and PR comment. Get review from `@security-team` (enforced by CODEOWNERS).

---

## Troubleshooting SCP AccessDenied Errors

### Identify if the denial is from an SCP

```bash
# Check the error message — SCP denials look like:
# "An error occurred (AccessDenied) when calling the CreateTopic operation:
#  Service control policy (SCP) implicitly denies access"

# Or check the IAM policy simulator:
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:role/my-role \
  --action-names sns:CreateTopic \
  --resource-arns "*"
```

### Find which SCP is blocking

```bash
# List all SCPs attached to the account's OUs
ACCOUNT_ID="666666666666"

# Get the account's OU
aws organizations list-parents \
  --child-id $ACCOUNT_ID \
  --query 'Parents[0]'

# List policies attached to that OU (walk up to root)
aws organizations list-policies-for-target \
  --target-id ou-xxxx-yyyyyyy \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,Id:Id}' \
  --output table
```

### Add an exemption to an existing SCP

1. Edit the relevant JSON in `security/scps/`
2. Add the role ARN to the `ArnNotLike` condition:
   ```json
   "ArnNotLike": {
     "aws:PrincipalArn": [
       "arn:aws:iam::*:role/AWSControlTowerExecution",
       "arn:aws:iam::*:role/cap-apply",
       "arn:aws:iam::ACCOUNT_ID:role/my-automation-role"   ← add here
     ]
   }
   ```
3. Open a PR, get `@security-team` approval

---

## SCP Reference — All Active Policies

| File | Target | What It Prevents |
|------|--------|-----------------|
| `deny-root-user.json` | Root | All API calls from root user |
| `deny-delete-cloudtrail.json` | Root | Deleting/stopping/modifying CloudTrail |
| `deny-disable-guardduty.json` | Root | Disabling GuardDuty detectors or members |
| `deny-public-s3.json` | Root | Removing S3 block-public-access, public ACLs |
| `require-encryption.json` | Workloads OU | Unencrypted S3 uploads, EBS volumes, RDS instances |
| `deny-region-restriction.json` | Workloads OU | API calls outside us-east-1 / us-west-2 |
| `require-mfa.json` | Prod OU | Non-MFA API calls (except session/MFA management) |

---

## SCP Size Limits

AWS limits each SCP to **5,120 characters** (after whitespace removal). If an SCP grows too large:
- Split into two SCPs targeting the same OU
- Use `NotAction` instead of listing every allowed action
- Move exemptions to a separate "exemption" SCP

Check current size:
```bash
wc -c security/scps/require-encryption.json
# Minified: jq -c . security/scps/require-encryption.json | wc -c
```
