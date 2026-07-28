# ADR-0002: Terraform for the foundation, CDK for the application layer

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0004](0004-s3-dynamodb-state-backend.md), [ADR-0008](0008-ssm-parameter-store-handoff.md)

## Context

The platform spans two kinds of resource with different rates of change and
different audiences.

**Foundational resources** — the organization, accounts, OUs, SCPs, VPCs, IAM,
KMS, the state backend — change rarely, are operated by the platform team, and
must be reproducible across accounts and regions. Some of them (Organizations,
account-level settings) have no CloudFormation coverage at all.

**Application resources** — APIs, functions, tables, queues, dashboards — change
constantly, are operated by product teams, and benefit from being expressed in
the same language as the application they belong to.

Using one tool for both means either the platform team writes TypeScript for
account vending, or product teams write HCL for a Lambda function. Both are
friction paid daily.

## Decision

Terraform owns the foundation layer (`terraform/`). AWS CDK in TypeScript owns
the application layer (`cdk/`). The boundary is the VPC: Terraform creates it
and everything beneath it; CDK consumes it and builds on top.

Values cross the boundary through SSM Parameter Store ([ADR-0008](0008-ssm-parameter-store-handoff.md)),
never through shared state.

## Alternatives considered

### Terraform for everything

Loses CDK's L2 and L3 constructs, which encode a great deal of AWS best practice
by default — a CDK `Queue` gets a dead-letter queue and encryption without
anyone remembering to ask. Application teams would write HCL, which most do not
know and which has no type checking against their application code.

### CDK for everything

CloudFormation cannot manage AWS Organizations, account creation, or several
account-level settings, so a Terraform or custom-resource escape hatch would be
needed regardless. CloudFormation stack limits and its update semantics — a
failed update rolls the whole stack back — are a poor fit for foundational
changes that must be applied incrementally and inspected.

### Pulumi for everything

Solves the language problem genuinely well. Rejected on ecosystem grounds: the
AWS provider surface, the module registry, and the available policy tooling
(Checkov, tfsec, Conftest, TFLint) are materially larger for Terraform, and the
team's existing operational knowledge is Terraform-shaped.

### CloudFormation directly

Verbose, no local type checking, and the same Organizations gap as CDK without
CDK's ergonomics.

## Consequences

### Positive

- Each layer uses the tool that fits its rate of change and its audience.
- Product teams write TypeScript alongside their application code.
- Foundational changes get Terraform's plan output, which is far easier to
  review than a CloudFormation change set.
- The full policy-as-code toolchain applies to the layer where a mistake is
  most expensive.

### Negative

- Two tools to install, learn, version and keep current.
- The boundary must be policed. A resource that could plausibly live in either
  layer will drift into both if nobody is watching.
- Cross-layer changes need coordination: Terraform applies first, CDK second.
- Two state mechanisms with different failure modes and different recovery
  procedures.

### Neutral

- Terraform pinned to `~> 1.9` with AWS provider `~> 5.0`.
- CDK uses TypeScript with `strict: true`.

## Compliance

`.github/CODEOWNERS` assigns `terraform/` and `cdk/` to the platform team.
Workflows `07`/`08` handle Terraform and `cdk-deploy.yml` handles CDK; neither
touches the other's directory.

## References

- [`docs/when-to-use/iac-selection.md`](../when-to-use/iac-selection.md)
