# Documentation Index

## How-To Guides — Step-by-Step Instructions

| Guide | When to Use |
|-------|-------------|
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
| [Decision Guide](architecture/decision-guide.md) | 10 key architecture decisions with rationale and trade-offs |

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
