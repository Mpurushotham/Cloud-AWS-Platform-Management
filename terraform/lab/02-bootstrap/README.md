# Lab Layer 02 — Bootstrap

> **Navigation:** [Lab README](../README.md) | [CI/CD Flow Diagram](../../../docs/architecture/diagrams/03-cicd-pipeline-flow.md) | [ADR-0005 OIDC](../../../docs/adr/0005-github-oidc-over-static-keys.md) | [ADR-0004 State Backend](../../../docs/adr/0004-s3-dynamodb-state-backend.md)

Creates the Terraform state backend and the keyless CI/CD identity that every
pipeline authenticates with. Depends on [layer 01](../01-governance/README.md)
for the access-log bucket.

## What it creates

| Resource | Purpose | Cost |
|----------|---------|------|
| S3 state bucket | Versioned, encrypted, TLS-only, access-logged, 90-day version retention | ~$0 |
| DynamoDB lock table | On-demand billing, PITR enabled | ~$0 |
| GitHub OIDC provider | Federates GitHub Actions JWTs into STS | $0 |
| `cap-plan` | Read-only + state read + lock | $0 |
| `cap-apply` | Admin, protected branch only, with deny guardrails | $0 |
| `cap-image-push` | ECR push scoped to `cap-*` repositories | $0 |
| `cap-prowler` | SecurityAudit + ViewOnly | $0 |
| KMS key (optional) | Only when `state_encryption = "aws:kms"` | **$1/month** |

## Apply

This layer creates the backend it will eventually live in, so it starts local
and migrates to itself.

```bash
cd terraform/lab/02-bootstrap
cp terraform.tfvars.example terraform.tfvars

# Wire in the access-log bucket from the governance layer
terraform -chdir=../01-governance output -raw access_logs_bucket_name

terraform init
terraform plan  -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Then migrate this layer's own state into the bucket it just created:

```bash
terraform output -raw backend_config    # copy, set key = "lab/bootstrap/terraform.tfstate"
# write it to backend.tf, then:
terraform init -migrate-state
```

## Wire the roles into GitHub

```bash
terraform output -raw github_cli_commands | bash
```

Repository variables, not secrets — role ARNs are not confidential, and using
variables makes them visible in workflow logs for debugging.

## Why the original bootstrap layer could not apply

`terraform/bootstrap/oidc.tf` attempts this:

```hcl
data "aws_iam_openid_connect_provider" "github" { url = "..." }

resource "aws_iam_openid_connect_provider" "github" {
  count = length(data.aws_iam_openid_connect_provider.github.arn) > 0 ? 0 : 1
  ...
}
```

A Terraform data source that matches nothing raises an error; it does not return
an empty value. In an account with no provider registered — exactly the state
this code branches on — the data source fails during plan and the `count`
expression is never evaluated. The condition can therefore never be false in the
only situation where it matters. This layer replaces the inference with an
explicit `create_oidc_provider` boolean.

## Encryption trade-off

`state_encryption` defaults to `AES256` because a customer-managed KMS key costs
$1/month and this lab is budgeted at $0. Terraform state stores resource
attributes in plaintext, which can include generated passwords and connection
strings, so **production should set `aws:kms`** to get an auditable key policy,
independent key rotation, and the ability to revoke access by key policy alone.
Recorded in [ADR-0015](../../../docs/adr/0015-lab-encryption-tradeoffs.md).

## Verification

```bash
aws s3api get-bucket-versioning  --bucket "$(terraform output -raw state_bucket_name)"
aws s3api get-bucket-encryption  --bucket "$(terraform output -raw state_bucket_name)"
aws s3api get-public-access-block --bucket "$(terraform output -raw state_bucket_name)"
aws dynamodb describe-table --table-name "$(terraform output -raw state_lock_table_name)" \
  --query 'Table.{Status:TableStatus,Billing:BillingModeSummary.BillingMode}'
aws iam list-open-id-connect-providers

# Confirm cap-apply cannot be assumed from a non-main ref
aws iam get-role --role-name cap-apply \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals'
```
