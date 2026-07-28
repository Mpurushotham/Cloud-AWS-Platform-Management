# ADR-0006: Service Control Policies as preventive guardrails

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** security-team, platform-team
- **Related:** [ADR-0003](0003-multi-account-landing-zone.md), [ADR-0011](0011-policy-as-code-gates.md)

## Context

Some rules must hold regardless of what any account administrator does: the
audit trail must not be stoppable, buckets must not become public, threat
detection must not be switchable off. IAM policies cannot express this, because
an account administrator can edit IAM policies — including the one meant to
restrain them.

Detective controls find these violations after the fact. For a small set of
rules, "after the fact" is too late.

## Decision

A small set of Service Control Policies is attached at the Root and OU level as
preventive guardrails. SCPs set the *maximum* available permission for member
accounts; nothing inside an account can exceed them.

Policy documents live in `security/scps/` and are consumed directly by Terraform
via `file()`, so the document reviewed in a pull request is byte-for-byte the
document enforced.

| SCP | Target | Prevents |
|-----|--------|----------|
| `deny-root-user` | Root | any root-user API call |
| `deny-delete-cloudtrail` | Root | stopping or deleting the trail |
| `deny-public-s3` | Root | public ACLs, removing public access blocks |
| `deny-disable-guardduty` | Root | disabling threat detection |
| `require-encryption` | Workloads OU | unencrypted S3, EBS, RDS |
| `deny-region-restriction` | Workloads OU | activity outside approved regions |
| `require-mfa` | Prod OU | non-MFA API calls |

## Alternatives considered

### IAM permission boundaries

Apply per principal, not per account, and must be attached to every principal to
be effective. Anyone who can create a role without a boundary escapes them.
Useful as a complement, insufficient as the mechanism.

### Detective-only: AWS Config plus auto-remediation

The window between violation and remediation is real. A bucket that is public
for four minutes has been public. Config is used as a second layer, not the
first.

### Deny-everything SCPs with narrow allow-lists

Maximally strict and operationally brittle: every new service adoption requires
an SCP change, so the SCP becomes a change-management bottleneck and is
eventually widened to `*` by someone in a hurry. Denying specific dangerous
actions ages better.

## Consequences

### Positive

- The listed actions cannot be performed by anyone in a member account,
  including its administrator.
- Enforcement is centralised and version-controlled.
- Guardrails survive IAM misconfiguration entirely.

### Negative

- **SCPs do not apply to the management account.** AWS exempts it without
  exception. Any workload in the management account is unguarded.
- A quota of 5 SCPs per target, with AWS-managed `FullAWSAccess` occupying one.
  The four root attachments sit exactly at quota; a fifth must be merged into an
  existing document.
- Debugging an SCP denial is unpleasant: the error is a generic `AccessDenied`
  with no indication that an SCP was responsible.
- A wrong SCP can lock every member account out simultaneously. They must be
  tested in a sandbox OU first.
- Automation principals need explicit `ArnNotLike` exemptions, and each exemption
  is a hole.

### Neutral

- SCP documents cap at 5120 bytes after whitespace removal, asserted by a
  Terraform precondition.

## A specific footgun in `require-encryption`

Its `DenyUnencryptedS3Uploads` statement denies any `s3:PutObject` that does not
carry an explicit `x-amz-server-side-encryption: aws:kms` header. Bucket
*default* encryption does not set that header. Services that write with default
encryption — CloudTrail, Config, ELB access logs, VPC flow logs — are therefore
denied.

It is attached to the Workloads OU only, and the audit buckets live outside that
scope. Before attaching it anywhere new, confirm every writer sends the header
explicitly.

## Compliance

Applied by `terraform/lab/01-governance/`. Attachment is asserted by
`scripts/lab-verify.sh` and by `06-compliance.yml`.

## Known limitation in the lab

Every lab resource lives in the management account, which is exempt. The seven
policies are attached and correct but enforce nothing until member accounts
exist. See [ADR-0013](0013-single-account-lab-profile.md).
