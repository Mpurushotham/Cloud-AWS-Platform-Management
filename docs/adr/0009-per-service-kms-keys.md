# ADR-0009: Per-service customer-managed KMS keys with rotation

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** security-team
- **Related:** [ADR-0015](0015-lab-encryption-tradeoffs.md)

## Context

Encryption at rest is required everywhere, but "encrypted" alone says little.
The questions that matter are: who can decrypt, can that be revoked without
touching IAM, is the decryption auditable, and does compromise of one key expose
unrelated data.

AWS-managed keys (`aws/s3`, `aws/rds`) encrypt correctly but answer none of
these well: their key policy cannot be edited, access follows IAM alone, and one
key covers every resource of that service in the account.

## Decision

Each service in each environment gets its own customer-managed KMS key with
automatic annual rotation enabled. Key aliases follow
`alias/cap/{env}/kms/{service}`.

Production keys use a 30-day deletion window. Key policies grant data-plane
operations (`Decrypt`, `GenerateDataKey`, `DescribeKey`) to named principals and
reserve administration to the account.

## Alternatives considered

### AWS-managed keys throughout

Free and zero-effort. Rejected because the key policy cannot be modified, so
access cannot be revoked at the key — only via IAM, which the resource owner may
control. Blast radius is also account-wide per service.

### One customer-managed key for the whole account

Cheaper ($1/month total) and gives an editable key policy. Rejected because it
recreates the blast-radius problem: revoking a compromised application's access
means editing a policy that every other service depends on.

### One key per resource

Maximum isolation, and unmanageable — key policies proliferate, cost scales
linearly, and the operational burden buys little over per-service isolation.

### Encryption at the application layer

Correct for a narrow class of data with strict custody requirements. As a
general mechanism it puts key management in application code, which is where it
is most likely to be done badly.

## Consequences

### Positive

- Access is revocable at the key policy, independent of IAM.
- Every `Decrypt` call is attributable in CloudTrail, per service.
- Compromise of one service's key does not expose another's data.
- Annual rotation is automatic; old key material is retained so existing
  ciphertext remains readable.
- A 30-day deletion window makes accidental key deletion recoverable.

### Negative

- **$1 per key per month, per environment.** Six services across four
  environments is $24/month before any API calls.
- KMS API calls are billed ($0.03 per 10,000 requests) and are in the hot path
  of every encrypt and decrypt. S3 bucket keys mitigate this substantially and
  are enabled everywhere.
- Key policies are a second authorisation system alongside IAM. A principal
  needs permission in both, and "access denied" with correct IAM is a confusing
  failure.
- A deleted key destroys its data irrecoverably. `prevent_destroy` and the
  deletion window are the mitigations.
- Some services cannot use SSE-KMS at all — S3 server access logging is the one
  encountered here.

### Neutral

- Rotation is annual, the AWS default.
- Multi-region keys are used only where a resource is genuinely replicated.

## Compliance

Checkov enforces `enable_key_rotation`. `.tflint.hcl` checks alias naming.
`scripts/lab-verify.sh` reports customer-managed keys because each is a
recurring charge.

## Lab deviation

The lab creates **no** customer-managed keys, because $1/month per key exceeds a
$0 budget. It uses AWS-managed and AWS-owned keys throughout and accepts the
weaker properties above. This is the single largest security compromise in the
lab profile and is recorded in [ADR-0015](0015-lab-encryption-tradeoffs.md).
