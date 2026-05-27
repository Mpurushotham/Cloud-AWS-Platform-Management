# Architecture Overview

## Multi-Account Organization Structure

```
Root (Management Account: 111111111111)
│
├── Core OU
│   ├── Landing Zone Account (222222222222)
│   │   └── Control Tower, Account Factory baseline
│   ├── Security Account (333333333333)
│   │   └── Security Hub aggregator, GuardDuty master, IAM Identity Center
│   └── Logging Account (444444444444)
│       └── CloudTrail org trail, Config aggregator, centralized S3
│
├── Infrastructure OU
│   └── Shared Services Account (555555555555)
│       └── ECR, Route53 private zones, ACM, Transit Gateway
│
├── Workloads OU
│   ├── Non-Prod OU
│   │   ├── Dev Account (666666666666)    VPC: 10.10.0.0/16
│   │   ├── Test Account (777777777777)   VPC: 10.11.0.0/16
│   │   └── Staging Account (888888888888) VPC: 10.20.0.0/16
│   └── Prod OU
│       └── Prod Account (999999999999)   VPC: 10.30.0.0/16
│
└── Sandbox OU
    └── Sandbox Account (000000000000)   VPC: 10.90.0.0/16
```

## SCP Guardrails (applied at OU level)

| SCP | Target | Effect |
|-----|--------|--------|
| deny-root-user | Root | Block all root API calls |
| deny-delete-cloudtrail | Root | Prevent CloudTrail deletion |
| deny-disable-guardduty | Root | Prevent GuardDuty disablement |
| deny-public-s3 | Root | Block S3 public access removal |
| require-encryption | Workloads OU | Enforce S3/EBS/RDS encryption |
| deny-region-restriction | Workloads OU | Allow us-east-1 + us-west-2 only |
| require-mfa | Prod OU | Block non-MFA API calls |

## Network Design

Each workload VPC contains three subnet tiers across 3 AZs:

```
VPC (10.{env}.0.0/16)
├── Public Subnets (/24 × 3 AZs)    — ALB only, no auto-assign public IP
├── Private Subnets (/22 × 3 AZs)   — EKS nodes, ECS tasks, egress via NAT GW
└── Isolated Subnets (/24 × 3 AZs)  — RDS, ElastiCache, no internet route
```

VPC Endpoints (all interface, private DNS enabled):
ECR API, ECR DKR, SSM, SSM Messages, EC2 Messages, Secrets Manager, STS,
CloudWatch Logs, KMS, X-Ray, plus S3 and DynamoDB gateway endpoints.

## Security Architecture (Defense in Depth)

```
Layer 1: SCP Guardrails (org-level, non-bypassable)
Layer 2: VPC/NACL/Security Groups (network-level)
Layer 3: WAF (application-level, API GW + ALB + CloudFront)
Layer 4: KMS Encryption (data-level, per service per environment)
Layer 5: IAM/IRSA (identity-level, least privilege)
Layer 6: GuardDuty (threat detection, network + API + S3 + EKS)
Layer 7: Security Hub (posture management, CIS + FSBP + PCI-DSS + NIST)
Layer 8: Kyverno (Kubernetes policy enforcement)
Layer 9: Falco (container runtime threat detection)
Layer 10: AWS Config (continuous compliance, drift detection)
Layer 11: CloudTrail (audit trail, all API calls)
```
