# Cloud-AWS-Platform-Management

Production-grade, multi-account AWS cloud platform implementing end-to-end DevSecOps, platform engineering, and compliance capabilities using **GitHub Actions**, **AWS CDK (TypeScript)**, and **Terraform**.

## Two profiles

This repository contains two implementations of the same architecture. Pick the
one that matches what you are doing.

| | [`terraform/environments/`](terraform/environments/) | [`terraform/lab/`](terraform/lab/) |
|---|---|---|
| **Purpose** | Target production design | Deployable free-tier lab |
| **Accounts** | 8, via Organizations | 1 |
| **Compute** | EKS, ECS, RDS Multi-AZ | Lambda |
| **Cost** | ~$400–600/month per environment | **$0/month** |
| **Status** | Reference design | **Deployed and verified** |

**New here?** Start with the lab — it deploys in about 45 minutes and costs
nothing: **[How to Set Up the Free-Tier Lab](docs/how-to/lab-setup-free-tier.md)**.

## Architecture

Diagrams are Mermaid in markdown and render inline on GitHub. They distinguish
what is deployed from what is designed.

| Diagram | Answers |
|---------|---------|
| [Organization Topology](docs/architecture/diagrams/01-organization-topology.md) | Account and OU layout; why SCPs do not restrict the management account |
| [Network Topology](docs/architecture/diagrams/02-network-topology.md) | Three-tier VPC; what removing NAT costs in capability |
| [CI/CD Pipeline Flow](docs/architecture/diagrams/03-cicd-pipeline-flow.md) | What runs when; how workflows authenticate without a stored secret |
| [Request Path](docs/architecture/diagrams/04-request-path.md) | End-to-end request flow and the Terraform → CDK handoff |
| [Security Layers](docs/architecture/diagrams/05-security-layers.md) | The 11 defence layers, which are live, and blast radius per compromise |
| [ADR Decision Tree](docs/architecture/diagrams/06-adr-decision-tree.md) | Which decision record answers the question you are holding |
| [Bootstrap Sequence](docs/architecture/diagrams/07-bootstrap-sequence.md) | Startup order and state recovery |

```
CI/CD Pipeline (GitHub Actions — numbered 00–10):
  00-pre-checks → 01-iac-security → 02-sast → 03-sca → 04-container
  → 05-dast → 06-compliance → 07-tf-plan → 08-tf-apply → 09-release
  → 10-lab-cost-guard

Security Layers (see the diagram for which are actually deployed):
  SCPs → VPC/NACLs → Security Groups → KMS → GuardDuty → Security Hub
  → Kyverno (K8s) → Falco (runtime) → AWS Config (drift) → CloudTrail
```

## Decisions

Sixteen [Architecture Decision Records](docs/adr/README.md) explain why the
platform is built this way, what the alternatives were, and what each choice
costs. The [decision tree](docs/architecture/diagrams/06-adr-decision-tree.md)
maps a question to the record that answers it.

## Repository Structure

```
Cloud-AWS-Platform-Management/
├── .github/workflows/     # 12 numbered + platform-specific CI/CD workflows
├── terraform/
│   ├── bootstrap/         # One-time org setup: state backend + OIDC roles
│   ├── environments/      # Per-account root modules (management/security/logging/...)
│   └── modules/           # 25 reusable Terraform modules
├── cdk/                   # CDK TypeScript: 6 L3 constructs + 6 application stacks
├── security/              # SCPs, Config rules, GuardDuty, WAF, IAM Identity Center
├── kubernetes/            # Kyverno policies, Falco rules, NetworkPolicies, Helm chart
├── ecs/                   # ECS task definitions and service configs
├── monitoring/            # CloudWatch dashboards, OpenSearch, PagerDuty integration
├── idp/                   # Internal Developer Platform: golden paths + Service Catalog
├── scripts/               # Automation: account vending, drift detection, SBOM
└── docs/                  # Architecture, runbooks, compliance mappings, onboarding
```

## Quick Start

### Prerequisites

```bash
# Install required tools
brew install terraform awscli node pre-commit tflint checkov tfsec conftest
npm install -g aws-cdk @commitlint/cli @commitlint/config-conventional

# Install pre-commit hooks
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg
```

### Phase 1 — Bootstrap (Run Once as Org Admin)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your org/account details

terraform init
terraform plan -out=tfplan
terraform apply tfplan

# After apply: migrate state to S3
terraform init -migrate-state
```

### Phase 2 — Deploy Platform Foundation

Push to `main` branch — `platform-foundation.yml` workflow runs automatically:
1. Logging account (CloudTrail, Config, S3 audit)
2. Security account (Security Hub, GuardDuty, IAM Identity Center)
3. Shared Services account (ECR, Route53, ACM, Transit Gateway)

### Phase 3 — Deploy Workload Environments

```bash
# Open a PR targeting main — 07-terraform-plan.yml runs plan across dev/staging/prod
# On merge: 08-terraform-apply.yml applies with appropriate approvals per environment
```

### Phase 4 — CDK Application Layer

```bash
cd cdk
npm install
npm test                    # CDK assertions must pass
npx cdk diff --all          # Review changes
# cdk-deploy.yml handles deployment on merge to main
```

## IaC Division of Responsibilities

| Layer | Tool | Reason |
|-------|------|--------|
| Organization, SCPs, OUs | Terraform | Stable org-level resources, mature AWS provider |
| Networking (VPC, TGW, DNS) | Terraform | Foundational, rarely changes |
| Security services (GuardDuty, Sec Hub, CloudTrail) | Terraform | One-per-account services |
| Shared services (ECR, Route53, ACM) | Terraform | Cross-account references via data sources |
| Application stacks (EKS, ECS, APIGW) | CDK TypeScript | Frequent iteration, type safety, stack deps |
| Observability stacks | CDK TypeScript | Dashboard/alarm code benefits from TypeScript loops |

## IAM Identity Center Permission Sets

| Permission Set | Accounts | Duration |
|----------------|----------|----------|
| PlatformAdmin | All accounts | 4h |
| Developer | Dev/Staging only | 8h |
| ReadOnly | All accounts | 12h |
| SecurityAuditor | Security + Logging | 4h |
| NetworkAdmin | Shared Services + Workloads | 4h |

## Security Controls Summary

| Control | Service | Scope |
|---------|---------|-------|
| Deny root API calls | SCP | Org-wide |
| Require encryption at rest | SCP + Config | Workloads OU |
| Deny public S3 buckets | SCP + Checkov | Org-wide |
| Require MFA | SCP | Prod OU |
| Centralized threat detection | GuardDuty | All accounts |
| Posture management | Security Hub (CIS 1.4 + FSBP + PCI-DSS + NIST 800-53) | All accounts |
| Container policy enforcement | Kyverno | EKS clusters |
| Runtime threat detection | Falco | EKS clusters |
| Secrets scanning | Gitleaks + detect-secrets | Pre-commit + CI |
| IaC policy-as-code | Checkov + tfsec + OPA | CI pipeline |

## Compliance Alignment

| Framework | Coverage |
|-----------|----------|
| SOC 2 Type II | AWS Config conformance pack + CloudTrail + Security Hub |
| PCI-DSS v3.2.1 | Security Hub standard + WAF + encryption SCPs |
| ISO 27001 | Config rules + GuardDuty + IAM Identity Center |
| CIS AWS Foundations v1.4 | Security Hub standard + Prowler CI scan |
| NIST 800-53 | Security Hub standard + Config rules |

## Naming Convention

All resources follow: `cap-{environment}-{component}`

Examples: `cap-prod-vpc`, `cap-dev-eks`, `cap-staging-kms-rds`

Standard tags applied to all resources:
- `Project=cap`
- `Environment={dev|staging|prod}`
- `ManagedBy={terraform|aws-cdk}`
- `CostCenter={value}`
- `Owner={team-name}`

## Contributing

See [docs/onboarding/new-team-onboarding.md](docs/onboarding/new-team-onboarding.md).

Pre-commit runs automatically. Follow [Conventional Commits](https://www.conventionalcommits.org/) format:
```
infra(networking): add vpc endpoints for secretsmanager
feat(eks): upgrade cluster to 1.30
security(scps): add deny-imdsv1 policy
```
