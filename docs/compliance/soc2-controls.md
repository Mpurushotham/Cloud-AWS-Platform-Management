# SOC 2 Type II — Platform Control Mapping

This document maps the SOC 2 Trust Service Criteria (TSC) to platform controls. Use this during audit preparation or when assessing whether a new architecture decision maintains SOC 2 alignment.

---

## CC1 — Control Environment

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC1.1 — COSO principles | AWS Organizations + IAM Identity Center enforces role separation | IAM IC permission sets in `security/iam-identity-center/permission-sets/` |
| CC1.2 — Board oversight | Security Hub aggregator with CRITICAL/HIGH finding escalation | EventBridge rule → SNS → PagerDuty |
| CC1.3 — Organizational structure | OU hierarchy enforces account isolation | `terraform/modules/organizations/` |
| CC1.4 — Commitment to competence | CODEOWNERS requires platform-team review of all IaC changes | `.github/CODEOWNERS` |
| CC1.5 — Accountability | CloudTrail org trail captures all API calls across all accounts | `terraform/modules/cloudtrail/` |

---

## CC2 — Communication and Information

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC2.1 — Quality information | AWS Config tracks configuration state of all resources | `terraform/modules/aws-config/` |
| CC2.2 — Internal communication | Security Hub findings routed to PagerDuty via EventBridge | `terraform/modules/security-hub/findings-routing.tf` |
| CC2.3 — External communication | WAF + CloudFront for external-facing APIs | `terraform/modules/waf/` |

---

## CC3 — Risk Assessment

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC3.1 — Risk identification | Prowler scans: CIS 1.4, AWS FSBP, NIST 800-53 | `06-compliance.yml` workflow |
| CC3.2 — Risk analysis | Security Hub aggregates and prioritizes findings | Security Hub console |
| CC3.3 — Change impact | `terraform plan` + OPA conftest gate on every PR | `07-terraform-plan.yml` |
| CC3.4 — Fraud risk | GuardDuty anomaly detection + Falco runtime monitoring | `terraform/modules/guardduty/`, `kubernetes/falco/` |

---

## CC4 — Monitoring Activities

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC4.1 — Ongoing monitoring | AWS Config continuous compliance + drift detection script | `06-compliance.yml`, `scripts/drift-detection.sh` |
| CC4.2 — Evaluation of deficiencies | Security Hub workflow status tracking (NEW → IN_PROGRESS → RESOLVED) | Security Hub findings |

---

## CC5 — Control Activities

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC5.1 — Control design | SCPs provide non-bypassable preventative controls | `security/scps/` |
| CC5.2 — Technology controls | IMDSv2 required, EBS encrypted, RDS encrypted (enforced by SCP + OPA) | `security/scps/require-encryption.json`, `conftest.rego` |
| CC5.3 — Policy implementation | pre-commit hooks enforce security before code reaches CI | `.pre-commit-config.yaml` |

---

## CC6 — Logical and Physical Access Controls

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC6.1 — Access control | IAM Identity Center with SSO — no shared credentials | `security/iam-identity-center/permission-sets/` |
| CC6.2 — New access | Account vending + SSO assignment workflow | `scripts/account-vending.py`, `docs/runbooks/account-vending.md` |
| CC6.3 — Access removal | IAM IC provides centralized deprovisioning (one action removes all account access) | IAM Identity Center |
| CC6.4 — Appropriate access | Least-privilege IRSA roles per service, no wildcard actions in prod | `terraform/modules/iam/roles.tf` |
| CC6.5 — MFA | `require-mfa` SCP blocks non-MFA API calls in Prod OU | `security/scps/require-mfa.json` |
| CC6.6 — Network security | VPC with 3-tier subnets, VPC endpoints, no IGW for private/isolated subnets | `terraform/modules/vpc/` |
| CC6.7 — Remote access | No SSH — SSM Session Manager only. Private EKS endpoint in prod | `terraform/modules/ec2-bastion/ssm.tf` |
| CC6.8 — Unauthorized software | Kyverno enforces ECR-only container registries | `kubernetes/kyverno/cluster-policies/allowed-registries.yaml` |

---

## CC7 — System Operations

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC7.1 — Vulnerability management | Trivy image scan + grype SCA in CI, cosign attestation | `03-sca.yml`, `04-container-security.yml` |
| CC7.2 — Anomaly detection | GuardDuty (network + API + S3 + EKS runtime) + Falco | `terraform/modules/guardduty/`, `kubernetes/falco/` |
| CC7.3 — Incident evaluation | Security Hub severity-based routing to PagerDuty | `terraform/modules/security-hub/findings-routing.tf` |
| CC7.4 — Incident response | P1-P4 runbook with GuardDuty/CloudTrail response procedures | `docs/runbooks/incident-response.md` |
| CC7.5 — Incident recovery | RDS Multi-AZ failover, cross-region DR procedure | `docs/runbooks/disaster-recovery.md` |

---

## CC8 — Change Management

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC8.1 — Change authorization | PR required for all IaC changes. Staging: 1 reviewer. Prod: 2 reviewers + 60-min wait | `08-terraform-apply.yml`, GitHub environment protection rules |

---

## CC9 — Risk Mitigation

| Criteria | Platform Control | Evidence Location |
|---------|-----------------|-----------------|
| CC9.1 — Vendor risk | Software composition analysis (grype, trivy) on all dependencies | `03-sca.yml` |
| CC9.2 — Business disruption | RDS Multi-AZ, EKS across 3 AZs, ALB health checks | Terraform environment configs |

---

## Availability (A1)

| Criteria | Platform Control | Evidence |
|---------|-----------------|---------|
| A1.1 — Capacity management | EKS HPA + Cluster Autoscaler, RDS storage autoscaling | EKS node group config, RDS storage config |
| A1.2 — Environmental threats | Multi-AZ deployment, no single AZ dependency | VPC subnet configuration |
| A1.3 — Recovery testing | Monthly backup restore test procedure | `docs/runbooks/disaster-recovery.md` |

---

## Confidentiality (C1)

| Criteria | Platform Control | Evidence |
|---------|-----------------|---------|
| C1.1 — Confidential information identification | KMS per-service encryption keys | `terraform/modules/kms/` |
| C1.2 — Confidential information disposal | S3 lifecycle rules, KMS key deletion window | `terraform/modules/s3/lifecycle.tf` |

---

## Evidence Collection for Auditors

For each SOC 2 audit period, collect:

```bash
# 1. CloudTrail logs (API access audit trail)
aws s3 sync s3://cap-audit-logs/cloudtrail/ ./audit-evidence/cloudtrail/

# 2. Config compliance snapshots
aws configservice get-compliance-summary-by-config-rule \
  --query 'ComplianceSummariesByConfigRule' > ./audit-evidence/config-compliance.json

# 3. Security Hub finding history
aws securityhub get-findings \
  --filters '{"WorkflowStatus":[{"Value":"RESOLVED","Comparison":"EQUALS"}]}' \
  --query 'Findings' > ./audit-evidence/resolved-findings.json

# 4. IAM access reviews (who has access to what)
aws iam generate-credential-report
aws iam get-credential-report --query 'Content' | base64 -d > ./audit-evidence/iam-credential-report.csv

# 5. Prowler compliance report
gh workflow run 06-compliance.yml -f environment=prod
# Download artifacts after completion
gh run download --name prowler-report
```
