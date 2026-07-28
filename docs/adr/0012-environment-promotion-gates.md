# ADR-0012: Graduated environment promotion gates

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0005](0005-github-oidc-over-static-keys.md), [ADR-0011](0011-policy-as-code-gates.md)

## Context

A change that reaches production carries a different cost of being wrong than
the same change reaching development. Applying one approval policy to both means
either development is slow or production is unprotected.

Approval also has a failure mode of its own: a reviewer who approves twenty
changes a day is not reviewing them. Requiring approval everywhere produces
rubber-stamping, which is worse than no gate because it looks like a control.

## Decision

Approval requirements scale with blast radius, implemented as GitHub environment
protection rules:

| Environment | Gate | Rationale |
|-------------|------|-----------|
| dev | auto-approve on merge to `main` | Merge already required review; a second approval adds delay, not safety |
| staging | 1 reviewer | Last point before production; a human confirms the plan matches intent |
| prod | 2 reviewers + 60-minute wait | Two independent readings, plus time for staging to reveal problems |

The 60-minute wait is a deliberate delay, not a queue.

## Alternatives considered

### Approval on every environment

Trains reviewers to approve reflexively. The dev gate would be clicked without
reading within a week, and that habit carries into the production gate.

### No approval anywhere, relying on tests

Works where tests fully characterise the change. Infrastructure changes are not
fully characterised by tests: a plan that destroys and recreates a database
passes every test and is still catastrophic.

### Time-based deployment windows

Restricting deploys to business hours concentrates risk into a narrow window and
delays urgent fixes. The wait timer achieves the useful part — elapsed time
between staging and production — without forbidding a deploy at 3am when one is
needed.

### Manual production deploys

Removes automation from the highest-risk path, which is backwards: production is
where reproducibility matters most.

## Consequences

### Positive

- Approval effort is spent where it changes outcomes.
- The wait timer converts "staging looked fine" into "staging has been fine for
  an hour".
- Gates are enforced by GitHub, not by workflow logic, so a workflow cannot vote
  itself past them.
- The environment protection rules are auditable and their approval history is
  retained.

### Negative

- **An urgent production fix waits 60 minutes.** A documented break-glass
  procedure is therefore mandatory, and every use of it must be reviewed
  afterwards — an unaudited break-glass path is just an unlocked door.
- Two production reviewers is a bottleneck for a small team, and out of hours it
  may be unmeetable.
- Environment protection rules are configured in GitHub, not in this repository,
  so they are not version-controlled and can be changed without a pull request.

### Neutral

- Production approvers are a named GitHub team.
- The same gates apply to CDK deploys and Terraform applies.

## Compliance

Configured in GitHub environment settings for `dev`, `staging` and `production`.
Consumed by `08-terraform-apply.yml`, `cdk-deploy.yml` and
`platform-foundation.yml`.

Because these settings live outside the repository, they should be audited
periodically — a change to them leaves no trace in the git history.
