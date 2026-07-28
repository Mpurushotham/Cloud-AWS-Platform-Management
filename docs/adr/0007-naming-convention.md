# ADR-0007: `cap-{environment}-{component}` naming convention

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0003](0003-multi-account-landing-zone.md)

## Context

Resource names appear in IAM policy ARNs, log queries, cost reports, alarm
descriptions and incident calls. Without a convention, names accrete
inconsistently — `prod-api`, `api-production`, `apiProd` — and every one of those
places needs a special case.

Names also matter for IAM: wildcard-scoped policies such as
`arn:aws:ecr:*:*:repository/cap-*` only work if the prefix is reliable.

## Decision

All resources are named `cap-{environment}-{component}`, lowercase, hyphen
separated.

- `cap` — the platform prefix, distinguishing platform resources from anything
  created by hand or by another team
- `{environment}` — `lab`, `dev`, `staging`, `prod`, `shared`, `security`,
  `logging`, `management`
- `{component}` — the resource's role: `vpc`, `api`, `items`, `sg-app`

KMS aliases use a path form because they permit slashes:
`alias/cap/{env}/kms/{service}`. SSM parameters likewise: `/cap/{env}/{path}`.

Every resource additionally carries the required tags `Project`, `Environment`,
`ManagedBy`, `CostCenter`, `Owner`, applied through `default_tags` on the
provider.

## Alternatives considered

### `{component}-{environment}`

Sorts by component, which reads well in a console listing. Rejected because it
makes prefix-based IAM wildcards useless — you cannot express "everything in
production" as a prefix.

### Including the region

`cap-us-east-1-prod-api` is long, and the region is already in every ARN. It
also makes names change when a resource is copied to another region, which
breaks the IAM policies referencing them.

### Random or generated suffixes

Guarantees global uniqueness for S3 and avoids collisions. Rejected for
human-facing resources: an incident call where nobody can say a bucket's name
out loud is worse than a collision. Account ID suffixes are used where global
uniqueness is genuinely required (`cap-lab-tfstate-<ACCOUNT_ID>`).

### Tags instead of names

Tags are for cost allocation and search; they cannot be used in an ARN, so IAM
scoping would fall back to `*`.

## Consequences

### Positive

- IAM policies can scope by prefix rather than enumerating ARNs.
- Cost reports group cleanly by environment.
- Log group and alarm names are predictable, so dashboards can be templated.
- Ownership of any resource is obvious from its name alone.

### Negative

- Some services impose length limits (IAM role names cap at 64 characters, S3
  bucket names at 63) and long component names hit them.
- Renaming a resource to conform means replacing it, which for stateful
  resources means downtime or a migration.
- Globally unique names (S3) need an account-ID suffix, breaking the pure form.

### Neutral

- Kubernetes resources follow their own namespace conventions; the prefix
  applies to AWS resources.

## Compliance

`conftest.rego` and `.tflint.hcl` check naming on Terraform plans.
`default_tags` on each provider block enforces the tag set, so an untagged
resource is not possible through Terraform.
