# ADR-0014: Eliminate account root credentials for daily work

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** security-team, platform-team
- **Related:** [ADR-0005](0005-github-oidc-over-static-keys.md), [ADR-0006](0006-scps-as-preventive-guardrails.md)

## Context

The lab was bootstrapped and operated from an account root session. AWS CLI v2's
`aws login` issues temporary root credentials, so `AccountAccessKeysPresent`
reports `0` — no persistent root access keys exist — while the account is
nonetheless being administered entirely as root.

Root is not a privileged IAM principal; it is outside the IAM system:

- it cannot be restricted by any IAM policy or permission boundary
- it is **exempt from every Service Control Policy**, including
  `cap-deny-root-user`, when acting in the management account
- it can close the account, change the payment method, and remove the account
  from the organization
- its compromise cannot be contained by anything this platform installs

Every control in this repository assumes the actor is an IAM principal. While
work is done as root, none of them are in the path.

## Decision

Root is used only for the tasks AWS permits nowhere else: closing the account,
changing the payment method, changing the account name or email, and restoring
an IAM state that locks everyone out.

All other work uses `cap-platform-admin`, an IAM role requiring MFA, limited to
one-hour sessions, carrying unconditional deny statements protecting CloudTrail,
the state encryption keys, and organization membership.

Layer `terraform/lab/00-identity/` creates the role and the account baseline. Its
README carries a cutover procedure that verifies the replacement identity works
*before* root is retired.

## Alternatives considered

### Keep using root, rely on MFA

MFA protects against credential theft, not against the absence of authorisation
limits. An MFA-authenticated root session still bypasses every SCP and every
permission boundary. It also leaves no way to grant a colleague partial access.

### An IAM user with `AdministratorAccess` and a permanent access key

Better than root, and still a long-lived credential that can leak and does not
expire. A role assumed with MFA gives short-lived credentials for the same
authority.

### IAM Identity Center permission sets

The right answer for an organisation with multiple humans, and the intended
destination. It is heavier to set up for a single operator, and it does not
change this ADR's conclusion — it is a better implementation of it.

### Delete the root credentials entirely

Not possible. Every AWS account has a root user permanently. The goal is
non-use, not deletion.

## Consequences

### Positive

- Daily work is performed by a principal that IAM can actually constrain.
- Sessions expire in an hour, so a leaked credential has a short life.
- Access can be granted to others by adding a principal to the trust policy,
  without sharing a credential.
- Actions are attributable to a role and a session, not to an anonymous root.
- The guardrail denies apply to the admin role even though they cannot apply to
  root.

### Negative

- **The cutover can lock you out** if the replacement identity is not verified
  first. The runbook's verification steps are not optional.
- MFA on every assumption is friction, deliberately.
- The role lives in the management account, so SCPs do not constrain it either —
  its guardrails are IAM-level and an operator who can edit IAM can remove them.
  This weakness disappears when the admin role lives in a member account.
- Root remains available and can still be used. Nothing technically prevents it;
  this is a discipline backed by monitoring.

### Neutral

- The account baseline (password policy, S3 public access block, default EBS
  encryption, IMDSv2 default) is applied in the same layer, since all of it is
  account-scoped and free.

## Compliance

`scripts/lab-verify.sh` checks `AccountAccessKeysPresent` (CIS 1.4) and reports
whether the identity layer was applied by root. The `applied_by_root` Terraform
output records it per apply.

Root usage should additionally be alarmed on — a CloudWatch metric filter on the
CloudTrail log group matching `$.userIdentity.type = "Root"` is the standard
control, and remains outstanding.

## References

- CIS AWS Foundations Benchmark v3.0, controls 1.4–1.7
- AWS Foundational Security Best Practices, `IAM.6`
