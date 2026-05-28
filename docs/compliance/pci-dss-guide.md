# PCI-DSS 4.0 — Platform Control Mapping

This guide maps PCI-DSS 4.0 requirements to platform controls. Use this when handling cardholder data (CHD) or preparing for a QSA assessment.

> **Scope note:** PCI scope applies to accounts and services that store, process, or transmit cardholder data (CHD). The CAP platform uses scope reduction through tokenization — only the payment-api service in the Prod account should be in-scope. All other services should never touch raw CHD.

---

## Requirement 1 — Network Security Controls

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 1.2.1 — All inbound/outbound restricted | Default-deny security groups + NACLs | `terraform/modules/vpc/`, `terraform/modules/nacl/` |
| 1.2.5 — All services allowed identified | VPC flow logs capture all traffic | `terraform/modules/vpc/flow-logs.tf` |
| 1.3.1 — DMZ for public components | 3-tier VPC: public (ALB only), private (ECS/EKS), isolated (RDS) | `terraform/modules/vpc/subnets.tf` |
| 1.3.2 — No direct routes from internet to CHD environment | Isolated subnets have no internet route | `terraform/modules/vpc/routing.tf` |
| 1.4.1 — NSC between trusted/untrusted networks | WAF on all external endpoints + ALB SG restricts to WAF only | `terraform/modules/waf/` |

---

## Requirement 2 — Secure Configurations

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 2.2.1 — All components have configuration standards | AWS Config conformance packs | `security/config-rules/conformance-packs/pci-dss-pack.yaml` |
| 2.2.7 — No insecure admin access | SSH disabled (SCP: no key pairs), SSM only | `terraform/modules/ec2-bastion/ssm.tf` |
| 2.3.1 — Wireless access restricted | No wireless networks in scope (cloud-only) | N/A |
| 2.3.2 — Vendor defaults changed | IMDSv2 required, root login blocked | `security/scps/deny-root-user.json` |

---

## Requirement 3 — Protect Stored Account Data

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 3.2.1 — SAD not retained post-auth | Stripe tokenization — raw PANs never stored in platform | Architecture decision |
| 3.4.1 — PAN rendered unreadable | KMS encryption for all storage (S3, RDS, EBS) | SCP `require-encryption.json` |
| 3.5.1 — Cryptographic key management | KMS per-service per-environment, auto-rotation, 30-day prod deletion window | `terraform/modules/kms/` |
| 3.7.1 — Key custodian policies | KMS key policies limit access to cap-apply and specific service roles | `terraform/modules/kms/policies.tf` |

---

## Requirement 4 — Protect Cardholder Data in Transit

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 4.2.1 — Strong cryptography in transit | TLS 1.2+ enforced on ALB, API GW, RDS (`rds.force_ssl=1`) | RDS parameter group, ALB listener policy |
| 4.2.1 — Trusted certificates | ACM manages all TLS certificates | `terraform/modules/acm/` |
| 4.2.2 — Wireless networks use strong crypto | No wireless in scope | N/A |

---

## Requirement 5 — Protect Systems from Malicious Software

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 5.2.1 — AV deployed on all components | GuardDuty Malware Protection for ECS/EKS + EBS | `terraform/modules/guardduty/` |
| 5.2.2 — AV kept current | GuardDuty managed by AWS (auto-updated signatures) | N/A |
| 5.3.2 — Periodic scans | GuardDuty continuous + Falco runtime + trivy scheduled | `06-compliance.yml` |
| 5.4.1 — Phishing protection | SCP denies unauthorized IAM role creation + MFA required | SCPs + require-mfa |

---

## Requirement 6 — Develop and Maintain Secure Systems

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 6.2.1 — Secure development | CodeQL SAST, semgrep, bandit in CI | `02-sast.yml` |
| 6.2.4 — Software engineering practices | OWASP checks via semgrep p/owasp-top-ten | `02-sast.yml` |
| 6.3.1 — Vulnerability identification | Trivy + grype SCA, SBOM generated per release | `03-sca.yml`, `09-release.yml` |
| 6.3.2 — Software inventory | SBOM (SPDX + CycloneDX) attached to every release | `09-release.yml` |
| 6.3.3 — All components protected | Patch pipeline: Dependabot + trivy + Checkov | `00-pre-checks.yml` |
| 6.4.1 — WAF on public-facing apps | WAF with OWASP managed rules on all public endpoints | `terraform/modules/waf/` |
| 6.4.2 — WAF in active blocking mode | WAF `default_action = block` in prod | `terraform/modules/waf/rules.tf` |
| 6.5.1 — Change control | PR-required workflow, reviewer gates | `08-terraform-apply.yml` |

---

## Requirement 7 — Restrict Access to System Components

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 7.2.1 — Access control system | IAM Identity Center with permission sets | `security/iam-identity-center/permission-sets/` |
| 7.2.2 — Least privilege | IRSA roles per service, no wildcard actions | `terraform/modules/iam/roles.tf` |
| 7.2.5 — Restrict privileged access | `PlatformAdmin` permission set session: 4 hours, MFA required | `security/iam-identity-center/permission-sets/platform-admin.json` |
| 7.3.1 — Access control system documented | Permission sets documented with allowed actions | `security/iam-identity-center/permission-sets/` |

---

## Requirement 8 — Identify Users and Authenticate

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 8.2.1 — Unique IDs for all users | IAM Identity Center — no shared accounts | IAM IC configuration |
| 8.2.2 — Group accounts not used | All OIDC CI/CD roles are per-workflow, not shared | `terraform/bootstrap/oidc.tf` |
| 8.3.4 — Password complexity | IAM IC password policy + MFA required | IAM IC settings |
| 8.3.6 — MFA for non-console access | `require-mfa` SCP + IAM IC MFA enforcement | `security/scps/require-mfa.json` |
| 8.4.2 — MFA for all access to CDE | MFA enforced at SSO level for prod accounts | IAM IC MFA settings |
| 8.6.1 — No hardcoded passwords | gitleaks + trufflehog scan all commits | `00-pre-checks.yml` |
| 8.6.2 — No interactive logins for system accounts | IRSA / OIDC for all automation — no static IAM access keys | `terraform/bootstrap/oidc.tf` |

---

## Requirement 9 — Restrict Physical Access

Physical access controls are managed by AWS (SOC 2 Type II, ISO 27001 certified data centers). Request AWS Artifact reports for evidence:

```bash
# Download AWS Compliance reports
# AWS Console → AWS Artifact → Reports → SOC 2 Type II
```

---

## Requirement 10 — Log and Monitor

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 10.2.1 — Audit log events | CloudTrail org trail captures all API calls | `terraform/modules/cloudtrail/` |
| 10.2.1.1 — Log individual access to CHD | RDS `log_connections` + `log_disconnections` enabled | `terraform/modules/rds/parameter-group.tf` |
| 10.2.1.2 — Log all root/admin access | Root login CloudWatch alarm | `monitoring/cloudwatch/alarms/security-alarms.json` |
| 10.3.2 — Log modification protection | `deny-delete-cloudtrail` SCP, S3 Object Lock on audit bucket | `security/scps/deny-delete-cloudtrail.json` |
| 10.3.3 — Log backups promptly | CloudTrail logs in S3 with versioning + replication | `terraform/modules/s3/` |
| 10.4.1 — Log review | Security Hub + GuardDuty findings reviewed daily via automated routing | `terraform/modules/security-hub/findings-routing.tf` |
| 10.5.1 — Log retention 12 months | CloudTrail S3 bucket lifecycle: 12 months immediate, 7 years Glacier | `terraform/modules/cloudtrail/` |
| 10.6.1 — Time synchronization | AWS managed NTP (automatic for all EC2/ECS/EKS) | N/A (AWS managed) |
| 10.7.1 — Failure of security controls detected | CloudWatch alarms on GuardDuty, Config, Security Hub | `monitoring/cloudwatch/alarms/` |

---

## Requirement 11 — Test Security

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 11.3.1 — External penetration testing | Prowler + OWASP ZAP as continuous scanning | `05-dast.yml`, `06-compliance.yml` |
| 11.3.2 — Internal penetration testing | Prowler CIS 1.4 + FSBP + PCI checks | `06-compliance.yml` |
| 11.4.1 — IDS/IPS techniques | GuardDuty network threat detection + Falco | `terraform/modules/guardduty/`, `kubernetes/falco/` |
| 11.5.1 — Intrusion detection | GuardDuty findings → PagerDuty within 5 minutes | `terraform/modules/security-hub/findings-routing.tf` |
| 11.6.1 — Change detection | AWS Config drift detection + `06-compliance.yml` drift detection | `scripts/drift-detection.sh` |

---

## Requirement 12 — Organizational Policies

| Sub-requirement | Platform Control | Evidence |
|----------------|-----------------|---------|
| 12.3.2 — Targeted risk analysis | Prowler reports mapped to risk | Prowler CSV output in CI artifacts |
| 12.5.2 — Scope documentation | Architecture overview + SCP attachment table | `docs/architecture/overview.md` |
| 12.10.1 — Incident response plan | Incident response runbook with P1-P4 | `docs/runbooks/incident-response.md` |

---

## PCI Scope Reduction Checklist

To keep PCI scope minimal:
- [ ] Raw PAN never touches any system — use Stripe payment element (JS tokenizes client-side)
- [ ] CHD never in logs (checked by semgrep `p/secrets` rules in CI)
- [ ] Payment-api is isolated in its own ECS service in isolated subnet
- [ ] Payment-api IRSA role has no access to non-payment resources
- [ ] RDS for payment-api is in a separate subnet group from other databases
- [ ] Network policy prevents other pods from reaching payment-api pods
- [ ] WAF blocks known card testing patterns on payment endpoints
