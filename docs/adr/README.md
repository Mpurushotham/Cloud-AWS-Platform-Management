# Architecture Decision Records

> **Navigation:** [Docs Index](../README.md) | [ADR Decision Tree](../architecture/diagrams/06-adr-decision-tree.md) | [Architecture Overview](../architecture/overview.md) | [Decision Guide](../architecture/decision-guide.md)

An ADR records **one decision**: what was decided, what the alternatives were,
why they lost, and what the decision costs. It is written when the decision is
made — while the arguments are still in someone's head — and never rewritten
afterwards. A decision that turns out to be wrong is superseded by a new ADR;
the original stays, because the reasoning that led to it is the useful part.

## Index

### Foundation

| ADR | Decision | Status |
|-----|----------|--------|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-terraform-foundation-cdk-application.md) | Terraform for foundation, CDK for application | Accepted |
| [0003](0003-multi-account-landing-zone.md) | Multi-account landing zone via Organizations | Accepted |
| [0004](0004-s3-dynamodb-state-backend.md) | S3 + DynamoDB state backend | Accepted |
| [0007](0007-naming-convention.md) | `cap-{environment}-{component}` naming | Accepted |
| [0008](0008-ssm-parameter-store-handoff.md) | SSM Parameter Store for Terraform → CDK handoff | Accepted |

### Security

| ADR | Decision | Status |
|-----|----------|--------|
| [0005](0005-github-oidc-over-static-keys.md) | GitHub OIDC instead of long-lived keys | Accepted |
| [0006](0006-scps-as-preventive-guardrails.md) | SCPs as preventive guardrails | Accepted |
| [0009](0009-per-service-kms-keys.md) | Per-service KMS keys with rotation | Accepted |
| [0010](0010-private-eks-endpoints-and-irsa.md) | Private EKS endpoints and IRSA | Accepted |
| [0014](0014-eliminate-root-access-keys.md) | Eliminate root credentials for daily work | Accepted |

### Delivery

| ADR | Decision | Status |
|-----|----------|--------|
| [0011](0011-policy-as-code-gates.md) | Policy-as-code gates in CI | Accepted |
| [0012](0012-environment-promotion-gates.md) | Graduated environment promotion gates | Accepted |

### Lab profile

| ADR | Decision | Status |
|-----|----------|--------|
| [0013](0013-single-account-lab-profile.md) | A separate single-account lab profile | Accepted |
| [0015](0015-lab-encryption-tradeoffs.md) | Where the lab accepts weaker encryption | Accepted |
| [0016](0016-no-nat-gateway-in-lab.md) | No NAT gateway in the lab | Accepted |

## Why a decision tree

The [decision tree](../architecture/diagrams/06-adr-decision-tree.md) sits on top
of this index and exists because **a list of sixteen documents does not answer a
question you are holding.**

An index is organised by the decision. A tree is organised by the *situation you
are in* — "I need to provision something", "this thing needs credentials",
"where does this resource go". You arrive with a problem, follow two or three
branches, and land on the record that already settled it. The index is for
someone who knows the answer exists; the tree is for someone who does not know
whether it does.

### How it helps, concretely

**It converts tacit knowledge into a lookup.** The reason a new engineer asks
"should this be Terraform or CDK?" is not that the answer is unwritten — it is
that they cannot tell which of sixteen documents contains it. Three branches get
them to ADR-0002 without asking anyone.

**It makes the *shape* of the architecture visible.** Reading the identity branch
shows immediately that there is no leaf labelled "static access key". The absence
is the point, and a prose index cannot show an absence. A tree can, because the
branch simply terminates in "Stop — not an approved option".

**It surfaces the questions nobody asked.** Building the encryption tree forced
the question "what if the service writing to this bucket cannot use SSE-KMS?",
which is exactly the constraint that governs the CloudTrail and access-log
buckets. The gap was found by drawing the tree, not by hitting it in production.

**It makes review cheap.** A reviewer can walk a change down the tree and see
whether it took an approved path. "This adds an interface endpoint" resolves in
seconds against the cost tree; without one it is an argument.

**It keeps the ADRs honest.** A branch with no ADR behind it is a decision that
was made implicitly. Every leaf here cites a record, and building the tree is
what revealed which decisions had never been written down — the lab profile,
the encryption trade-off and the NAT omission all became ADRs 0013, 0015 and
0016 because the tree had leaves pointing nowhere.

### What it is worth

| Benefit | What it replaces |
|---------|------------------|
| Decisions are found, not re-litigated | The same architecture argument, quarterly, with no new information |
| Onboarding reads a map instead of a wiki | Weeks of asking colleagues what the conventions are |
| Reviews cite a record instead of an opinion | "I'd have done it differently" as a blocking comment |
| Reversals are deliberate | Silent drift away from a decision nobody remembers making |
| Constraints are explicit | Discovering the constraint in production |

The cost is roughly twenty minutes per decision, at the moment you are already
holding all the context. The alternative is paying for that context again, with
interest, every time somebody asks why.

### What it is not

It is not a substitute for judgement, and it is not a policy engine. A tree
covers the decisions that have already been made; a genuinely new situation
falls off the end of a branch, and that is the signal to write a new ADR rather
than to force the situation into an existing leaf.

## Writing a new ADR

1. Copy [`template.md`](template.md) to `NNNN-short-title.md`, taking the next
   free number.
2. Fill in **Context** before **Decision** — if the context does not make the
   decision feel inevitable, the context is incomplete.
3. Be specific in **Alternatives considered**. "We considered X but chose Y"
   with no reason is not a record, it is a note.
4. Fill in **Consequences** honestly, including the negative ones. An ADR with
   no downsides listed is a sales pitch and will not be trusted.
5. Add the ADR to the index above, and to the
   [decision tree](../architecture/diagrams/06-adr-decision-tree.md) if it
   answers a recurring question.

## Status values

| Status | Meaning |
|--------|---------|
| Proposed | Under discussion, not yet binding |
| Accepted | In force; the codebase reflects it |
| Deprecated | No longer applied to new work; existing usage remains |
| Superseded by ADR-NNNN | Replaced; kept for the reasoning it contains |

Never delete an ADR and never edit its Decision section after acceptance. If the
decision changes, write a new one and mark the old one superseded — the record
of *why you once thought otherwise* is what stops the same ground being covered
again in a year.
