# ADR-0013: A separate single-account lab profile

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0003](0003-multi-account-landing-zone.md), [ADR-0015](0015-lab-encryption-tradeoffs.md), [ADR-0016](0016-no-nat-gateway-in-lab.md)

## Context

`terraform/environments/` implements the target design: eight accounts, EKS per
environment, RDS Multi-AZ, Transit Gateway, OpenSearch, WAF, Shield. Applying
`terraform/environments/dev` alone provisions an EKS cluster, three NAT
gateways, an RDS instance and a WAF web ACL — roughly **$400–600 per month** —
and assumes an `AWSControlTowerExecution` role in a member account that does not
exist.

The available environment is one AWS account on a free-tier plan with a $1
zero-spend budget alarm, no member accounts, and no Control Tower.

There is no variable setting that turns the environment configuration into
something deployable there. The gap is architectural, not parametric.

## Decision

`terraform/lab/` is a parallel implementation of the same architecture, sized to
run at $0 in a single account. It is a sibling of `terraform/environments/`, not
a fork of it and not a mode of it.

Five ordered layers: identity, governance, bootstrap, network, workload. The OU
tree, SCP set, naming convention, tagging, state layout and CI roles are
identical to the target. What differs is what is deployed inside them.

## Alternatives considered

### Add `enable_*` variables to the existing environment modules

The obvious approach, and it fails on the shape of the difference. The lab needs
a *different topology* — no Control Tower execution role, no cross-account
provider assumption, non-overlapping subnet arithmetic, no NAT — not the same
topology with parts disabled. Encoding both in one module means every resource
gains a conditional, every conditional needs testing in both modes, and the
production path becomes harder to read in order to support a lab that production
never uses.

### Deploy the environment code and accept the cost

$400–600/month against a $1 budget alarm. Not available.

### Create real member accounts with plus-addressed emails

Would make the SCP layer genuinely enforcing, which is the lab's biggest gap.
Rejected for now: free-tier accounts are frequently blocked from creating
organization member accounts, and a closed account sits in a 90-day quarantine —
so a failed experiment is unrecoverable for a quarter.

### Use LocalStack

Excellent for unit-testing Terraform. Does not exercise IAM evaluation,
Organizations, SCP behaviour or real service quotas, which is most of what this
platform is about.

### Plan-only, never apply

Validates syntax and catches some errors. Would not have caught the RDS
non-ASCII description rejection, the `Decimal` serialisation failure, or the
fact that the original bootstrap OIDC configuration cannot apply at all — all
three were found by applying.

## Consequences

### Positive

- The whole platform can be deployed, exercised and torn down at $0.
- Production module readability is preserved; no conditional exists solely for
  the lab.
- The lab is a genuine test of the design's *shape*, and it found real defects.
- Layer boundaries, naming, tagging and state layout transfer unchanged.

### Negative

- **Two implementations of a similar design will drift.** A fix applied to one
  must be considered for the other, and nothing enforces that.
- The lab cannot validate anything that depends on account separation — which is
  the most important property of the target architecture.
- **SCPs enforce nothing in the lab.** Every resource lives in the management
  account, which AWS exempts from all SCPs. The policies are attached and
  correct but inert.
- Someone may mistake the lab for a production-ready configuration. Each layer
  README states the trade-offs explicitly for this reason.

### Neutral

- The lab uses `cap-lab-*` naming, so its resources never collide with an
  environment deployment.
- `terraform/environments/` is left unchanged by this ADR.

## Compliance

`scripts/lab-verify.sh` asserts that no billable resource exists and that the
governance controls are present. `10-lab-cost-guard.yml` runs it on a schedule.

## What would retire this ADR

Creating real member accounts for logging, security and one workload environment.
That single change makes the SCP layer enforcing and removes the largest
divergence between lab and target.
