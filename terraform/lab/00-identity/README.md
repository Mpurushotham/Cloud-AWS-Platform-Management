# Lab Layer 00 — Identity

> **Navigation:** [Lab README](../README.md) | [ADR-0014 Root Credential Elimination](../../../docs/adr/0014-eliminate-root-access-keys.md) | [Security Best Practices](../../../docs/security/security-best-practices.md)

Retires account-root access keys and establishes `cap-platform-admin` as the identity
that every later lab layer runs as. Apply this layer **before** any other.

## Why this layer exists

The lab was bootstrapped from an account **root session**. Check which situation
you are in before following the procedure below — the remediation differs:

```bash
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent'
# 0 = no long-lived root access keys exist (the good case)
# 1 = persistent root access keys exist and must be deleted
```

AWS CLI v2's `aws login` produces a temporary root session rather than stored
keys, so an account can show `0` here and still be operated entirely as root.
That is the situation this layer addresses.

Either way, root is the wrong identity for daily work. A root principal cannot be
scoped by IAM policy, is exempt from every Service Control Policy, ignores
permission boundaries, and cannot be constrained by the guardrails this platform
installs. Everything the platform claims to enforce is bypassed while you are
signed in as root — including the SCPs applied one layer later.

## What it creates

| Resource | Purpose | Cost |
|----------|---------|------|
| `cap-platform-admin` IAM role | MFA-gated admin identity, 1h max session | $0 |
| Guardrail inline policy | Unconditional deny on CloudTrail teardown, state-key deletion, org exit | $0 |
| Account password policy | CIS 1.8/1.9 — 14 chars, complexity, 90-day rotation, 24 reuse history | $0 |
| Account S3 public access block | CIS 2.1.4 — no bucket in the account can be public | $0 |
| EBS encryption by default | CIS 2.2.1 | $0 |
| EC2 instance metadata defaults | IMDSv2 required region-wide | $0 |

## Apply

```bash
cd terraform/lab/00-identity
cp terraform.tfvars.example terraform.tfvars
# Set break_glass_principal_arns to your IAM user ARN:
aws iam list-users --query 'Users[].Arn' --output text

terraform init
terraform plan  -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

## Stop signing in as root — cutover procedure

Current state of this account, for reference:

| Fact | Value |
|------|-------|
| Account alias | `muktha-ab` → `https://muktha-ab.signin.aws.amazon.com/console` |
| Organizations account name | `muktha-ab` |
| Root access keys | none (good) |
| Day-to-day IAM user | `muktha-aws` |
| **MFA on `muktha-aws`** | **none — this blocks the cutover** |
| `muktha-aws` standing privilege | `AdministratorAccess` + 9 redundant policies via group `muktha-aws-ug` |

### The ordering is not optional

```
1. Enrol MFA on the IAM user          <- do this first
2. Prove role assumption works        <- verify before removing anything
3. Strip the user's standing admin    <- only now
```

Doing step 3 before step 1 leaves the user unable to do anything and root as the
only way back in — the exact situation this layer exists to eliminate.

### Step 1 — Enrol MFA on `muktha-aws`

The role's trust policy requires `aws:MultiFactorAuthPresent = true`, so without
a device the user cannot assume it at all.

Do this in the console, so the seed never lands in a terminal history or a
transcript:

1. Sign in to `https://muktha-ab.signin.aws.amazon.com/console` as `muktha-aws`
2. **IAM → Users → muktha-aws → Security credentials**
3. **Assign MFA device** → authenticator app → scan the QR code
4. Enter two consecutive codes

Confirm:

```bash
aws iam list-mfa-devices --user-name muktha-aws --query 'MFADevices[].SerialNumber' --output text
```

### Step 2 — Configure the profiles and prove assumption works

```bash
aws configure --profile cap-iam-user     # muktha-aws access key + secret, region us-east-1
terraform output -raw aws_config_profile_snippet >> ~/.aws/config
# edit ~/.aws/config: set mfa_serial to the ARN from step 1
```

Then verify. This must return an **assumed-role** ARN, not a user or root ARN:

```bash
aws sts get-caller-identity --profile cap-lab
# arn:aws:sts::<ACCOUNT_ID>:assumed-role/cap-platform-admin/botocore-session-...
```

If this fails, stop and fix it before continuing. Do not proceed to step 3.

### Step 3 — Remove the user's standing admin

Only after step 2 succeeds. `muktha-aws` currently holds `AdministratorAccess`
directly through its group, which means an attacker holding just the access key
gets full admin **without ever presenting MFA** — the second factor is bypassed
entirely because the privilege does not depend on it.

This layer has already attached `cap-assume-platform-admin`, which grants the
user everything it legitimately needs: self-service credentials, self-service
MFA, and `sts:AssumeRole` on the admin role. The group policies are therefore
redundant as well as dangerous.

```bash
# Review what is attached
aws iam list-attached-group-policies --group-name muktha-aws-ug \
  --query 'AttachedPolicies[].[PolicyName,PolicyArn]' --output text

# Detach them all
aws iam list-attached-group-policies --group-name muktha-aws-ug \
  --query 'AttachedPolicies[].PolicyArn' --output text \
  | tr '\t' '\n' \
  | while read -r arn; do
      [ -n "$arn" ] && aws iam detach-group-policy --group-name muktha-aws-ug --policy-arn "$arn" \
        && echo "detached $arn"
    done

# Confirm the user now holds only the assume-role policy
aws iam list-attached-user-policies --user-name muktha-aws --query 'AttachedPolicies[].PolicyName' --output text
aws iam list-attached-group-policies --group-name muktha-aws-ug --query 'AttachedPolicies[].PolicyName' --output text
```

After this, `muktha-aws` alone can do almost nothing; `AWS_PROFILE=cap-lab`
does everything, and only with MFA present.

### Step 4 — Use the role by default

```bash
echo 'export AWS_PROFILE=cap-lab' >> ~/.zshrc
```

This also makes the MCP servers in [`.mcp.json`](../../../.mcp.json) run as
`cap-platform-admin` rather than as root — see
[the MCP documentation](../../../docs/mcp/README.md#2-authentication).

---

## Root key retirement — reference

Do **not** skip the verification steps. Deleting your only working credential before
confirming the replacement works will lock you out of the account.

**1. Confirm the IAM user has its own access key and an MFA device.**

```bash
aws iam list-access-keys      --user-name muktha-aws
aws iam list-mfa-devices      --user-name muktha-aws
```

If the user has no access key, create one *while still authenticated as root*:

```bash
aws iam create-access-key --user-name muktha-aws
```

**2. Store the IAM user credentials as a source profile.**

```bash
aws configure --profile cap-iam-user      # paste the IAM user's key/secret, region us-east-1
```

**3. Add the role profile.** Use the `aws_config_profile_snippet` output verbatim:

```bash
terraform output -raw aws_config_profile_snippet >> ~/.aws/config
```

Replace `<your-mfa-device-name>` with the serial from step 1.

**4. Verify the replacement identity works.** This must succeed and must return the
`cap-platform-admin` ARN, not root:

```bash
aws sts get-caller-identity --profile cap-lab
# Expect: arn:aws:sts::<account>:assumed-role/cap-platform-admin/botocore-session-...
```

**5. Retire root.**

*If `AccountAccessKeysPresent` was `1`* — delete the keys. This cannot be done
via the CLI or Terraform; AWS requires the console:

- Sign in as root → top-right account menu → **Security credentials**
- **Access keys** → *Deactivate* each key, confirm nothing breaks, then *Delete*

*If it was `0`* — there is nothing to delete. Retiring root means changing your
habit: stop running `aws login` as root, and use `AWS_PROFILE=cap-lab` for all
subsequent work. Confirm root is genuinely unused by checking that its last
activity stops advancing:

```bash
aws iam generate-credential-report >/dev/null && sleep 5
aws iam get-credential-report --query 'Content' --output text | base64 --decode \
  | awk -F, 'NR==1 || $1=="<root_account>" {print $1, $5, $10}'
```

**6. Confirm.** Re-running this layer with `AWS_PROFILE=cap-lab` should show:

```bash
terraform output applied_by_root   # false
```

## Verification

```bash
# Role exists and is MFA-gated
aws iam get-role --role-name cap-platform-admin \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'

# Account baseline
aws iam get-account-password-policy
aws s3control get-public-access-block --account-id "$(aws sts get-caller-identity --query Account --output text)"
aws ec2 get-ebs-encryption-by-default
```

## Known limitation

`cap-platform-admin` lives in the Organizations **management account**, which AWS
exempts from all Service Control Policies. The guardrail deny statements in
`roles.tf` are IAM-level and therefore *are* enforced against this role, but an
operator who can edit IAM can also remove them. In a real multi-account deployment
the platform admin role lives in a member account where SCPs apply and this
weakness disappears. See [ADR-0013](../../../docs/adr/0013-single-account-lab-profile.md).
