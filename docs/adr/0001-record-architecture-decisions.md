# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR Index](README.md), [Decision Tree](../architecture/diagrams/06-adr-decision-tree.md)

## Context

This platform makes a large number of decisions that are expensive to revisit:
which IaC tool owns which resource, how accounts are separated, how CI
authenticates, which encryption applies where. Each was decided with reasons
that were obvious at the time and invisible six months later.

The failure mode is specific and repeats: someone encounters a constraint they
do not recognise, assumes it is accidental, removes it, and rediscovers the
original reason in production. Code shows *what* was built. Git history shows
*when*. Neither shows *why*, or which alternatives were rejected and on what
grounds.

Comments do not solve this — they are attached to one file, while an
architectural decision spans many. Wikis do not solve it either, because they
drift out of the repository and out of code review.

## Decision

We record every architecturally significant decision as a numbered Markdown file
in `docs/adr/`, committed alongside the code it governs, and reviewed in the
same pull request as the change that implements it.

A decision is architecturally significant if reversing it would require changing
code in more than one component, or if a reasonable engineer might undo it
without knowing why it exists.

## Alternatives considered

### A wiki or Confluence space

Lives outside the repository, so it is not reviewed with the change, cannot be
required by branch protection, and has no mechanism to stay in sync. Every
wiki-based architecture record eventually describes a system that no longer
exists.

### Long-form comments in the code

Work well for local decisions and badly for cross-cutting ones. A decision about
account topology has no single file to live in, and duplicating it across files
guarantees the copies diverge.

### Commit messages

Correct location, wrong discoverability. Finding the reasoning requires knowing
which commit to look for, which requires already knowing the answer.

## Consequences

### Positive

- Reasoning is versioned with the code and reviewed with it.
- Onboarding reads a decision log rather than interviewing colleagues.
- Rejected alternatives are recorded, so they are not silently re-proposed.
- The absence of an ADR for a recurring question is itself a signal.

### Negative

- Roughly twenty minutes of writing per decision, paid at the moment the author
  wants to move on.
- ADRs can rot if superseded records are not marked. Mitigated by never editing
  an accepted Decision section and always superseding explicitly.
- Judgement is required about what counts as significant. Too low a bar produces
  noise; too high a bar defeats the purpose.

### Neutral

- The MADR-style format in [`template.md`](template.md) is the house style.
- Numbers are permanent. A superseded ADR keeps its number and its file.

## Compliance

`.github/pull_request_template.md` asks whether the change requires an ADR.
Reviewers are expected to request one when a pull request encodes a decision
that is not written down.

## References

- Michael Nygard, *Documenting Architecture Decisions* (2011)
- [MADR](https://adr.github.io/madr/)
