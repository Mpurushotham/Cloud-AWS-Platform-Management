## Description

<!-- Briefly describe what this PR does and why -->

## Type of Change

- [ ] Infrastructure (Terraform)
- [ ] Application (CDK)
- [ ] Security policy change
- [ ] Kubernetes manifest
- [ ] CI/CD workflow
- [ ] Documentation
- [ ] Bug fix
- [ ] Refactor

## Pre-Merge Checklist

### IaC (Terraform / CDK)
- [ ] `terraform fmt` has been run
- [ ] `terraform validate` passes in all affected environments
- [ ] Checkov scan: no new CRITICAL findings (`checkov -d terraform/`)
- [ ] tfsec scan: no new HIGH+ findings (`tfsec terraform/`)
- [ ] OPA/conftest policy check passes (`conftest test tfplan.json`)
- [ ] CDK unit tests pass (`npm test` in `cdk/`)

### Security
- [ ] No secrets or credentials in code (pre-commit gitleaks passed)
- [ ] New resources follow naming convention `cap-{env}-{component}`
- [ ] New resources have all required tags: `Project`, `Environment`, `ManagedBy`, `CostCenter`, `Owner`
- [ ] New S3 buckets have public access block enabled
- [ ] New KMS keys have `enable_key_rotation = true`
- [ ] New EC2/ECS/EKS workloads use IRSA or IAM roles (no static credentials)

### Testing
- [ ] Changes tested in dev environment first
- [ ] Terraform plan reviewed in PR comments (auto-posted by workflow)
- [ ] No unexpected resource deletions in plan output

### Documentation
- [ ] Module README updated (if Terraform module changed)
- [ ] `docs/` updated for architectural changes
- [ ] Runbook updated for operational procedure changes

## Rollback Plan

<!-- How to revert this change if it causes issues in production -->

## Related Issues / Tickets

<!-- Link to Jira/Linear/GitHub Issues -->

## Architecture Decision Records

<!-- List any ADRs this PR implements or relates to -->
