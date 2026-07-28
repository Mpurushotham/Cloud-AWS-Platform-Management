# ADR-0005: GitHub OIDC federation instead of long-lived IAM keys

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team, security-team
- **Related:** [ADR-0012](0012-environment-promotion-gates.md), [ADR-0014](0014-eliminate-root-access-keys.md)

## Context

CI needs AWS credentials with enough authority to create infrastructure. The
conventional approach — an IAM user's access key stored as a GitHub secret — has
a specific and well-documented failure profile:

- the credential never expires, so a leak is permanent until noticed
- it is visible to every workflow in the repository, including ones added later
- rotation is manual and therefore does not happen
- a fork or a malicious pull request that can influence a workflow can exfiltrate it
- CloudTrail shows the IAM user, not which workflow or branch acted

## Decision

All CI authentication uses GitHub's OIDC provider federated into AWS STS. No AWS
access key exists in GitHub, in any environment, for any purpose.

Four roles are defined, each with a trust policy constrained on the `sub` claim:

| Role | `sub` condition | Permissions |
|------|-----------------|-------------|
| `cap-plan` | `StringLike repo:ORG/REPO:*` | ReadOnly + state read + lock |
| `cap-apply` | `StringEquals repo:ORG/REPO:ref:refs/heads/main` | Admin + deny guardrails |
| `cap-image-push` | `StringEquals …:ref:refs/heads/main` | ECR push to `cap-*` only |
| `cap-prowler` | `StringLike repo:ORG/REPO:*` | SecurityAudit + ViewOnly |

Every trust policy also asserts `aud = sts.amazonaws.com`.

## Alternatives considered

### IAM user access keys in GitHub secrets

The status quo being replaced. See the failure profile above.

### A self-hosted runner with an instance profile

Removes the stored credential, but introduces a persistent host to patch,
monitor and isolate. A self-hosted runner processing pull requests from forks is
a well-known code-execution risk. Higher operational cost for a weaker outcome.

### AWS IAM Roles Anywhere

Designed for workloads outside AWS holding X.509 certificates. GitHub already
issues OIDC tokens natively, so this adds certificate lifecycle management for
no gain.

### A single OIDC role for all workflows

Simpler, and wrong. A plan running on an untrusted pull request would hold the
same authority as an apply on `main`. The value of OIDC here is precisely that
authority can differ per branch.

## Consequences

### Positive

- No long-lived AWS credential exists in GitHub. There is nothing to leak.
- Credentials expire with the job, typically within minutes.
- Authority is bound to a branch by the `sub` claim, enforced by AWS rather than
  by workflow logic. A fork's pull request cannot mint a token matching
  `ref:refs/heads/main`.
- CloudTrail records the assumed role and the token's subject, so the acting
  workflow is identifiable.
- Nothing to rotate.

### Negative

- The trust policy is easy to get subtly wrong. `StringLike` with a trailing
  wildcard on `repo:ORG/*` would trust every repository in the organisation; a
  missing `aud` condition permits token replay from another relying party.
- Debugging a failed assumption means reading a decoded JWT claim set, which is
  less obvious than "the key is wrong".
- Renaming the repository or the default branch silently breaks every trust
  policy referencing it.
- Requires `permissions: id-token: write` on each job, which is easy to forget.

### Neutral

- The OIDC provider is created once per account.
- Role ARNs are stored as GitHub *variables*, not secrets — they are not
  confidential and being visible in logs aids debugging.

## Compliance

Trust conditions are asserted in
[`terraform/lab/02-bootstrap/README.md`](../../terraform/lab/02-bootstrap/README.md).
`scripts/lab-verify.sh` checks that the provider and roles exist. Any workflow
introducing `aws-access-key-id` fails review.

## Implementation note

The original `terraform/bootstrap/oidc.tf` could not apply: it used a data
source to test whether the provider existed, but a Terraform data source that
matches nothing raises an error rather than returning empty, so the conditional
could never evaluate in the case it was written for. Replaced by an explicit
`create_oidc_provider` boolean.
