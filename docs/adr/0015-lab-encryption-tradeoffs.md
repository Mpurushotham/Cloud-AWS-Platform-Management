# ADR-0015: Where the lab accepts weaker encryption

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team, security-team
- **Related:** [ADR-0009](0009-per-service-kms-keys.md), [ADR-0013](0013-single-account-lab-profile.md)

## Context

[ADR-0009](0009-per-service-kms-keys.md) requires a customer-managed KMS key per
service per environment. A customer-managed key costs **$1/month** regardless of
use. The lab's budget is $0, enforced by an existing $1 zero-spend alarm.

The lab needs encryption on the Terraform state bucket, the CloudTrail bucket,
the access-log bucket and the DynamoDB tables. Under ADR-0009 that is four keys,
$4/month — small in absolute terms and outside the constraint.

Recording this as an explicit decision matters more than the amount. An
undocumented deviation from a security standard looks identical to an oversight,
and the next person to read the code cannot tell which it is.

## Decision

The lab uses AWS-managed and AWS-owned keys instead of customer-managed keys:

| Resource | Lab | Production |
|----------|-----|------------|
| Terraform state bucket | SSE-S3 (`AES256`) + bucket keys | SSE-KMS, customer-managed |
| CloudTrail bucket | SSE-S3 | SSE-KMS, customer-managed |
| Access-log bucket | SSE-S3 (**required** — see below) | SSE-S3 (still required) |
| DynamoDB tables | AWS-owned key | Customer-managed key |
| EBS volumes | account-default encryption | Customer-managed key |

`terraform/lab/02-bootstrap` exposes `state_encryption`, which accepts
`"aws:kms"` and creates a rotating customer-managed key with a proper key policy.
It defaults to `AES256`. **Production must set `aws:kms`.**

## What is actually lost

Not confidentiality at rest — all of the above is encrypted with AES-256 and AWS
manages the key material to the same standard. What is lost is control:

- **No editable key policy.** Access is governed by IAM alone. There is no second
  authorisation layer, and no way to revoke access at the key.
- **No independent revocation.** Disabling a customer-managed key instantly
  denies all decryption; there is no equivalent for an AWS-managed key.
- **Coarser blast radius.** One AWS-managed key per service per account, rather
  than isolation between services.
- **Weaker attribution.** `Decrypt` calls against AWS-owned keys are not
  individually visible in the account's CloudTrail.
- **Rotation is not yours to schedule.** AWS rotates on its own cadence.

For a lab holding synthetic data, all five are acceptable. For anything holding
real data, none of them are.

## One case where this is not a trade-off

**S3 server access logging cannot deliver into an SSE-KMS bucket.** The access-log
bucket uses SSE-S3 in production too. This is an AWS constraint, not a cost
decision, and it is the reason the encryption decision tree has a branch for
"does a service write logs into this bucket".

## Alternatives considered

### One shared customer-managed key for the whole lab

$1/month total, and would preserve the editable-key-policy property. Rejected
because the budget is $0, not $1 — but this is the first thing to change if any
budget becomes available. It buys most of the benefit for the least money.

### No encryption at all

Not possible and not desirable: S3 and DynamoDB encrypt by default, and turning
that off would be strictly worse for no saving.

### Application-layer encryption

Moves key management into code and does not remove the need for at-rest
encryption underneath.

## Consequences

### Positive

- The lab runs at $0 while remaining encrypted at rest everywhere.
- The production path is implemented and testable by flipping one variable.
- The deviation is explicit, so nobody has to guess whether it was intentional.

### Negative

- The lab does not exercise KMS key policies, so a key-policy error would not be
  caught until production.
- `state_encryption = "AES256"` in a `terraform.tfvars` copied into a real
  environment silently weakens it. The variable description and the layer README
  both warn about this; nothing enforces it.
- Terraform state contains resource attributes that may include generated
  passwords. In the lab it is protected by bucket policy and IAM alone.

### Neutral

- Bucket keys are enabled everywhere, which reduces KMS request cost when the
  KMS path is enabled.

## Compliance

`scripts/lab-verify.sh` reports any customer-managed key, since each is a
recurring charge. Checkov's KMS rules are suppressed only for the lab directory,
with this ADR cited as the reason.
