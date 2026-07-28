# ADR-0004: S3 with DynamoDB locking for Terraform state

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0002](0002-terraform-foundation-cdk-application.md), [ADR-0015](0015-lab-encryption-tradeoffs.md)

## Context

Terraform state records the mapping between configuration and real resources. It
must be shared (several engineers and CI apply the same configuration), locked
(concurrent applies corrupt it), versioned (recovery from a bad write), and
protected (it contains resource attributes, sometimes including secrets).

Local state fails all four. The question is which remote backend.

## Decision

State lives in a versioned, encrypted S3 bucket with a DynamoDB table for
locking. One state file per layer, keyed `{layer}/terraform.tfstate`.

The bucket has versioning enabled, public access blocked, a TLS-only bucket
policy, server access logging to a central bucket, `prevent_destroy` set, and a
lifecycle rule retaining 10 noncurrent versions for 90 days.

## Alternatives considered

### Terraform Cloud / HCP Terraform

Genuinely good: managed state, locking, policy enforcement, and a run history
UI. Rejected because it introduces a third-party dependency in the critical path
of infrastructure recovery — if the platform is down and the vendor is also
down, you cannot apply. Self-hosting the state in the account being managed
keeps recovery within one blast radius. Cost also scales per user.

### S3 without DynamoDB locking

On Terraform 1.9 there is no native S3 locking, so concurrent applies silently
interleave writes. The resulting state describes infrastructure that never
existed, and the failure is discovered later, during an unrelated apply.

### Terraform 1.10+ native S3 locking (`use_lockfile`)

The right answer once the version pin moves. It removes the DynamoDB table
entirely by using a conditional S3 write. This repository pins `~> 1.9`, so it
is not available yet. **This ADR should be revisited when the pin moves to
1.10 or later.**

### Consul or etcd

Operational burden with no benefit over S3 for this use case.

## Consequences

### Positive

- State survives loss of any workstation.
- Concurrent applies fail loudly rather than corrupting state.
- Versioning makes a bad write recoverable by copying back the previous object
  version.
- Access is controlled by IAM and auditable in CloudTrail.

### Negative

- A bootstrap chicken-and-egg: the layer that creates the bucket must start on
  a local backend and migrate to itself.
- A stuck lock requires `terraform force-unlock`, which is dangerous if an apply
  really is still running.
- The state bucket becomes a high-value target — it describes the entire estate.
- One more DynamoDB table to monitor and pay for, however little.

### Neutral

- State keys follow `{layer}/terraform.tfstate`.
- The lock table uses on-demand billing; lock traffic is negligible.

## Compliance

Bucket configuration is asserted by the verification commands in
[`terraform/lab/02-bootstrap/README.md`](../../terraform/lab/02-bootstrap/README.md).
Checkov rules on S3 encryption, versioning and public access apply in CI.

## Lab deviation

The lab bucket uses SSE-S3 rather than a customer-managed KMS key, because a CMK
costs $1/month against a $0 budget. Production should use `aws:kms`. See
[ADR-0015](0015-lab-encryption-tradeoffs.md).
