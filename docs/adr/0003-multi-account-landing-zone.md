# ADR-0003: Multi-account landing zone via AWS Organizations

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team, security-team
- **Related:** [ADR-0006](0006-scps-as-preventive-guardrails.md), [ADR-0013](0013-single-account-lab-profile.md)

## Context

Workloads at different sensitivity and maturity levels must be separated in a
way that survives an IAM mistake. Within a single account, separation depends
entirely on IAM policy being correct — and IAM policy is exactly the thing most
likely to be wrong, because it is edited constantly by people under time
pressure.

The AWS account is the only boundary that is not policy-dependent. Service
quotas, blast radius, cost allocation, and — critically — Service Control
Policy enforcement are all account-scoped.

## Decision

Workloads are separated by AWS account, grouped into Organizational Units by
function and environment:

```
Root
├── Core OU            landing zone, security, logging
├── Infrastructure OU  shared services
├── Workloads OU
│   ├── Non-Prod OU    dev, test, staging
│   └── Prod OU        production
└── Sandbox OU         time-boxed experimentation
```

OUs are the attachment point for Service Control Policies. Accounts, not IAM
policies, are the primary isolation boundary.

## Alternatives considered

### A single account with IAM-based separation

Every boundary depends on policy correctness. A single over-permissive policy
exposes production to a development workload. Service quotas are shared, so a
dev load test can exhaust production's Lambda concurrency. Cost allocation
depends on tag discipline that nobody sustains. Rejected.

### One account per team

Attractive for autonomy, but SCPs attach to OUs and environments cut across
teams — a "require MFA in production" guardrail has no natural OU to live in
when production spans twelve team accounts. Team separation is better expressed
with IAM Identity Center permission sets inside environment accounts.

### One account per application

Correct for very large estates and disproportionate here: account vending,
network attachment and baseline configuration multiply per application, and
Transit Gateway attachment costs are per-account.

### AWS Control Tower as the sole mechanism

Control Tower is used for account factory and baseline guardrails, but not as
the only interface — it does not cover every control this platform needs, and
its landing zone updates have their own release cadence. Terraform manages what
Control Tower does not.

## Consequences

### Positive

- Blast radius is bounded by an account, not by policy correctness.
- SCPs become available as a genuinely non-bypassable control.
- Service quotas are per-account, so environments cannot starve each other.
- Cost allocation is exact without depending on tagging.

### Negative

- Cross-account access needs explicit role assumption, which is more work than
  a same-account call.
- Networking requires Transit Gateway or peering, which costs money per
  attachment per hour.
- Account vending must be automated or it becomes the bottleneck.
- Observability must be aggregated deliberately; nothing is centralised by
  default.
- **A member account cannot be deleted quickly.** Closed accounts sit in a
  90-day quarantine, which makes experimentation expensive.

### Neutral

- The management account holds no workloads — it exists to run Organizations
  and consolidate billing.
- Email addresses for member accounts must be unique; plus-addressing works.

## Compliance

`terraform/environments/management/` defines the OU tree and account set.
`terraform/lab/01-governance/` creates the same OU structure in the lab.
Drift is detected by `06-compliance.yml`.

## Known limitation in the lab

The lab has **zero member accounts**, so this ADR describes the target rather
than the deployed state. Every consequence above that depends on account
separation is currently unrealised. See [ADR-0013](0013-single-account-lab-profile.md).
