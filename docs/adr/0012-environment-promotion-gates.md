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

Configured in GitHub environment settings for `dev`, `staging`, `production`
and `management`. Consumed by `08-terraform-apply.yml`, `cdk-deploy.yml` and
`platform-foundation.yml`.

Because these settings live outside the repository, they should be audited
periodically — a change to them leaves no trace in the git history:

```bash
for env in dev staging production management; do
  printf "%-12s " "$env"
  gh api "repos/<owner>/<repo>/environments/$env" \
    --jq '[.protection_rules[] | if .type=="required_reviewers" then "reviewers=\(.reviewers|length)"
           elif .type=="wait_timer" then "wait=\(.wait_timer)m" else .type end] | join("  ")'
done
```

## Deviations from this ADR in the current deployment

Recorded rather than quietly tolerated:

| Intended | Actual | Why |
|----------|--------|-----|
| dev auto-approves | **1 required reviewer** | `terraform/environments/dev` provisions EKS, NAT gateways and RDS — roughly $400–600/month — into member accounts that do not exist. Until they do, an unattended dev apply is a cost and blast-radius risk rather than a convenience. Revert to auto-approve once the accounts exist and a dev apply is genuinely routine. |
| prod requires 2 reviewers | **1 required reviewer** | The organisation currently has one human. Two distinct approvers is unsatisfiable, and configuring it would deadlock every production deploy. Raise to 2 as soon as there is a second person. |
| approval is independent | **self-approval permitted** | With one human, `prevent_self_review` would deadlock. This means the gate currently enforces *deliberateness* — a conscious click — not separation of duties. That is a materially weaker property and should not be described as peer review. |

The 60-minute production wait timer **is** configured as specified.
