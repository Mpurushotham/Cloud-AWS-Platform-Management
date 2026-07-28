# ADR-0011: Policy-as-code gates in CI

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team, security-team
- **Related:** [ADR-0006](0006-scps-as-preventive-guardrails.md), [ADR-0012](0012-environment-promotion-gates.md)

## Context

Most infrastructure misconfigurations are known patterns: a bucket without
encryption, a security group open to `0.0.0.0/0` on port 22, an unrotated KMS
key, an instance permitting IMDSv1. They are individually obvious and
collectively unmissable by human review, because reviewers read diffs for intent
and not for a checklist of forty controls.

Finding these after deployment means remediation, an incident record, and a
window of exposure. Finding them in a pull request means an edit.

## Decision

Every pull request runs a layered set of automated gates before merge is
possible:

| Gate | Tool | Catches |
|------|------|---------|
| Secrets | gitleaks | credentials committed to the repo |
| IaC misconfiguration | Checkov, tfsec | known insecure resource configurations |
| IaC lint | TFLint | provider misuse, deprecated arguments, naming |
| Custom policy | Conftest / OPA | rules specific to this platform |
| SAST | CodeQL, Semgrep, Bandit | application code vulnerabilities |
| Dependencies | Trivy, Grype | vulnerable and outdated packages |
| Containers | Hadolint, Trivy image | Dockerfile issues, base image CVEs |
| Cost | Infracost | unexpected spend in the plan |

Ordered cheapest-first, so a commit with a leaked secret fails in seconds rather
than after an image build.

## Alternatives considered

### Human review alone

Necessary for intent, unreliable for checklists. Reviewer attention is a scarce
resource best spent on whether the change is *right*, not on whether encryption
is enabled.

### Detective-only scanning of deployed infrastructure

Prowler and Config run on a schedule and are valuable, but they find problems
after exposure has begun. They are the second line, not the first.

### A single all-in-one scanner

No single tool has full coverage. Checkov and tfsec disagree on real findings in
both directions; CodeQL and Semgrep have different strengths. Overlap is
tolerated deliberately.

### Warning-only gates

A gate that does not block is a log line nobody reads. Gates fail the build.

## Consequences

### Positive

- Known misconfigurations cannot reach an account.
- Feedback arrives in the pull request, when the change is still cheap to edit.
- The rule set is version-controlled and reviewable, so "why is this blocked"
  has a written answer.
- Custom Conftest policies encode platform-specific rules no vendor ships.

### Negative

- **False positives are the main cost.** Each needs a suppression with a
  justification, and a suppression file that grows unexamined is how a gate
  quietly stops working. `.checkov.yml` skips must carry a reason.
- CI time increases materially — a full run is several minutes.
- Tool versions drift; a scanner that adds a rule can break unrelated pull
  requests. Versions are pinned and upgraded deliberately.
- Gates can be bypassed by an administrator, so branch protection must forbid it.

### Neutral

- Findings are uploaded as SARIF and surface in GitHub's security tab.
- Conftest policies live in `conftest.rego` and run against `terraform show -json`.

## Compliance

Workflows `00`–`04` and `07`. Branch protection requires them to pass. Suppression
entries in `.checkov.yml` require an inline reason.

## Relationship to SCPs

Policy-as-code catches what it knows about, in the pull request. SCPs
([ADR-0006](0006-scps-as-preventive-guardrails.md)) catch what happens outside
the pipeline entirely — console changes, direct API calls, anything applied by
someone bypassing CI. Both are needed: one has coverage, the other has
authority.
