# Documentation Index

## Start here

| Document | When to Use |
|----------|-------------|
| [Set Up the Free-Tier Lab](how-to/lab-setup-free-tier.md) | **Deploy the whole platform into one account at $0/month.** The fastest way to see it work end to end |
| [Architecture Diagrams](architecture/diagrams/README.md) | Understand the system visually before reading any code |
| [ADR Index](adr/README.md) | Find out *why* the platform is built this way |
| [Known Issues](security/known-issues.md) | What is broken, what is deliberately deferred, and why |

---

## How-To Guides — Step-by-Step Instructions

| Guide | When to Use |
|-------|-------------|
| [Set Up the Free-Tier Lab](how-to/lab-setup-free-tier.md) | Deploying the single-account lab profile from scratch |
| [Bootstrap the Platform](how-to/bootstrap-platform.md) | Standing up the platform in a new AWS Organization from scratch |
| [Deploy a New Environment](how-to/deploy-new-environment.md) | Adding a new account (uat, perf) or environment to the platform |
| [Add a New Service](how-to/add-new-service.md) | Deploying a new microservice, API, or background worker |
| [Use the CI/CD Pipeline](how-to/ci-cd-pipeline.md) | Understanding workflow stages, fixing failures, adding new steps |
| [Manage SCPs](how-to/manage-scps.md) | Adding guardrails, troubleshooting AccessDenied, adding exemptions |
| [Deploy Kubernetes Workloads](how-to/kubernetes-workloads.md) | EKS Helm deployments, Kyverno policies, IRSA, network policies |
| [Manage Secrets and Rotation](how-to/secrets-and-rotation.md) | Storing secrets, rotation, emergency credential revocation |
| [Set Up Observability](how-to/observability-setup.md) | CloudWatch dashboards, alarms, X-Ray tracing, PagerDuty |

---

## When-to-Use Decision Guides

| Guide | Answers |
|-------|---------|
| [IaC Selection](when-to-use/iac-selection.md) | Terraform vs CDK vs manual — which tool for which resource |
| [Compute Selection](when-to-use/compute-selection.md) | EKS vs ECS Fargate vs Lambda vs EC2 |
| [Storage Selection](when-to-use/storage-selection.md) | S3 vs RDS vs ElastiCache vs DynamoDB vs EFS |

---

## Architecture

| Document | Contents |
|----------|---------|
| [Overview](architecture/overview.md) | Multi-account org structure, SCP table, network design, defense-in-depth layers |
| [Diagrams](architecture/diagrams/README.md) | Seven Mermaid diagrams: org, network, CI/CD, request path, security, decision tree, bootstrap |
| [Decision Guide](architecture/decision-guide.md) | 10 key architecture decisions with rationale and trade-offs |

---

## Architecture Decision Records

| Document | Contents |
|----------|---------|
| [ADR Index](adr/README.md) | All 16 records, plus why the decision tree exists and what it is worth |
| [ADR Decision Tree](architecture/diagrams/06-adr-decision-tree.md) | Question → the record that answers it |
| [Template](adr/template.md) | Format for writing a new one |

Foundation: [0001](adr/0001-record-architecture-decisions.md) ·
[0002](adr/0002-terraform-foundation-cdk-application.md) ·
[0003](adr/0003-multi-account-landing-zone.md) ·
[0004](adr/0004-s3-dynamodb-state-backend.md) ·
[0007](adr/0007-naming-convention.md) ·
[0008](adr/0008-ssm-parameter-store-handoff.md)

Security: [0005](adr/0005-github-oidc-over-static-keys.md) ·
[0006](adr/0006-scps-as-preventive-guardrails.md) ·
[0009](adr/0009-per-service-kms-keys.md) ·
[0010](adr/0010-private-eks-endpoints-and-irsa.md) ·
[0014](adr/0014-eliminate-root-access-keys.md)

Delivery: [0011](adr/0011-policy-as-code-gates.md) ·
[0012](adr/0012-environment-promotion-gates.md)

Lab profile: [0013](adr/0013-single-account-lab-profile.md) ·
[0015](adr/0015-lab-encryption-tradeoffs.md) ·
[0016](adr/0016-no-nat-gateway-in-lab.md)

---

## Security

| Document | Contents |
|----------|---------|
| [Security Best Practices](security/security-best-practices.md) | What is enforced, how, and what is not — with CIS and FSBP mapping |
| [Known Issues](security/known-issues.md) | Open defects and accepted risks, with status |

---

## Tooling

| Document | Contents |
|----------|---------|
| [AWS MCP Servers](mcp/README.md) | Connecting Claude Code to AWS: which servers, skills vs plugins vs servers, performance limits, security, and which architectures are natively supported |

---

## Compliance

| Document | Contents |
|----------|---------|
| [SOC 2 Controls](compliance/soc2-controls.md) | TSC criteria mapped to platform controls + evidence collection commands |
| [PCI-DSS Guide](compliance/pci-dss-guide.md) | PCI-DSS 4.0 requirements mapped to platform controls + scope reduction checklist |

---

## Runbooks — Operational Procedures

| Runbook | When to Use |
|---------|-------------|
| [Account Vending](runbooks/account-vending.md) | Provisioning a new AWS member account |
| [Incident Response](runbooks/incident-response.md) | GuardDuty/Security Hub findings, credential compromise, production rollback |
| [Disaster Recovery](runbooks/disaster-recovery.md) | RDS failover, cross-region DR, backup verification |

---

## Onboarding

| Guide | Audience |
|-------|---------|
| [New Team Onboarding](onboarding/new-team-onboarding.md) | Teams deploying their first service on the platform |
