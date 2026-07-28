# Architecture Diagrams

> **Navigation:** [Docs Index](../../README.md) | [Architecture Overview](../overview.md) | [ADR Index](../../adr/README.md)

Diagrams are written as [Mermaid](https://mermaid.js.org/) inside markdown, so
they render natively on GitHub, diff line-by-line in pull requests, and need no
build step or external tool. A diagram that cannot be reviewed in a PR drifts
from the system within a release or two.

## Index

| # | Diagram | Answers |
|---|---------|---------|
| 01 | [Organization Topology](01-organization-topology.md) | How are accounts and OUs arranged, and why do SCPs not restrict the management account? |
| 02 | [Network Topology](02-network-topology.md) | What does the VPC look like, and what does removing NAT actually cost in capability? |
| 03 | [CI/CD Pipeline Flow](03-cicd-pipeline-flow.md) | What runs when, which gate stops what, and how does a workflow get credentials without a stored secret? |
| 04 | [Request Path](04-request-path.md) | What happens to a request end to end, and how does Terraform hand off to CDK? |
| 05 | [Security Layers](05-security-layers.md) | What are the eleven defence layers, which are actually deployed, and what is the blast radius of each compromise? |
| 06 | [ADR Decision Tree](06-adr-decision-tree.md) | Which ADR answers the question I am holding? |
| 07 | [Bootstrap Sequence](07-bootstrap-sequence.md) | In what order does the platform come up, and how do I recover broken state? |

## Placeholders

This repository is public, so real identifiers are replaced with placeholders.
Resolve them against your own deployment:

| Placeholder | Get the real value with |
|-------------|-------------------------|
| `<ACCOUNT_ID>` | `aws sts get-caller-identity --query Account --output text` |
| `<ORG_ID>` | `aws organizations describe-organization --query 'Organization.Id' --output text` |
| `<ROOT_ID>` | `aws organizations list-roots --query 'Roots[0].Id' --output text` |
| `<OU_*>` | `terraform -chdir=../../../terraform/lab/01-governance output organizational_unit_ids` |
| `<VPC_ID>` | `terraform -chdir=../../../terraform/lab/03-network output -raw vpc_id` |
| `<API_ID>` | `terraform -chdir=../../../terraform/lab/04-workload output -raw api_id` |

An account ID is not formally a secret, but publishing it next to the role names
and the OIDC trust subject tells a reader exactly which roles to target in a
known account. The placeholders cost nothing and remove that.

## Convention

Diagrams distinguish what is **deployed** from what is **designed**:

| Style | Meaning |
|-------|---------|
| Green fill | deployed and verified in account <ACCOUNT_ID> |
| Orange fill | partially deployed, or deployed with a caveat |
| Red fill | a real risk or an unenforceable control |
| Dashed grey | designed and written, but switched off — usually on cost grounds |

A diagram showing eleven healthy security layers when four are running is worse
than no diagram, because it is believed. Where the lab diverges from the target
architecture, both are shown and the gap is named.

## Updating

Edit the markdown. There is nothing to regenerate. When a diagram and the
Terraform disagree, the Terraform is right and the diagram is a bug — the
verification commands in each layer's README are the way to check.
