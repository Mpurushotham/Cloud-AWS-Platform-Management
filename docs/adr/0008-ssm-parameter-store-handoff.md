# ADR-0008: SSM Parameter Store for the Terraform → CDK handoff

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0002](0002-terraform-foundation-cdk-application.md), [ADR-0004](0004-s3-dynamodb-state-backend.md)

## Context

[ADR-0002](0002-terraform-foundation-cdk-application.md) splits provisioning
between Terraform and CDK. CDK stacks need values Terraform owns: VPC IDs,
subnet IDs, security group IDs, table ARNs. Something has to carry them across
the boundary.

## Decision

Terraform writes the values CDK needs into SSM Parameter Store under
`/cap/{environment}/…`. CDK reads them at synth time.

```
/cap/lab/api/id              /cap/lab/table/name
/cap/lab/api/endpoint        /cap/lab/table/arn
/cap/lab/api/execution-arn   /cap/lab/function/name
/cap/lab/alarms/topic-arn    /cap/lab/function/arn
```

Parameters use the Standard tier, which is free and effectively unlimited.

## Alternatives considered

### CDK reads Terraform remote state

`terraform_remote_state` in reverse: CDK would need read access to the state
bucket. State contains every attribute of every resource in the account — far
more than the handful of IDs CDK needs, including anything sensitive Terraform
happens to have recorded. Granting CDK that access to obtain a VPC ID is a
serious over-grant, and it couples CDK to Terraform's state format.

### CloudFormation exports and `Fn::ImportValue`

The idiomatic CloudFormation answer, with a well-known failure: an exported
value cannot be modified or deleted while any stack imports it. This produces
stacks that cannot be updated and cannot be deleted, and unpicking it means
temporarily rewriting every consumer. It also does not work across accounts.

### Hard-coded IDs in `cdk.json` context

Works until Terraform replaces a resource, at which point CDK deploys against an
ID that no longer exists. The failure is silent and arrives later.

### A shared data store — DynamoDB or S3 JSON

Reinvents Parameter Store without versioning, IAM path scoping, or console
support.

## Consequences

### Positive

- Loose coupling: CDK depends on a small, named contract rather than on
  Terraform's internals.
- IAM can scope read access per path, so a stack sees only its own environment.
- Parameters are versioned, and the previous value is recoverable.
- Works across accounts and regions with a resource policy.
- Values are visible in the console, which makes debugging trivial.

### Negative

- The contract is implicit. Renaming a parameter breaks CDK at synth time with
  a "parameter not found" error, and nothing catches it earlier.
- Ordering matters: Terraform must apply before CDK synthesises. A CI pipeline
  that runs them in parallel will fail intermittently.
- Another API call in the synth path, and another IAM permission to grant.
- Standard-tier parameters have a 4 KB value limit — fine for IDs, not for
  documents.

### Neutral

- `SecureString` is available for sensitive values, but Secrets Manager is
  preferred for anything that needs rotation.
- Parameter names are lowercase, slash-separated, environment-scoped.

## Compliance

Parameters are written by `terraform/lab/04-workload/ssm.tf` and listed in that
layer's `ssm_parameter_names` output. CDK stacks read them via
`ssm.StringParameter.valueFromLookup`.
