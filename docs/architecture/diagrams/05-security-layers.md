# Security Architecture — Defence in Depth

> **Navigation:** [Diagram Index](README.md) | [Security Best Practices](../../security/security-best-practices.md) | [Known Issues](../../security/known-issues.md) | [ADR-0006 SCPs](../../adr/0006-scps-as-preventive-guardrails.md)

## Eleven layers, and which of them the lab actually has

The value of layering is that no single control is load-bearing. The table below
is honest about what is deployed today versus what the target design specifies —
a diagram that shows eleven green layers when four are running is worse than no
diagram.

```mermaid
graph TD
    A["<b>1. SCP guardrails</b><br/>organization-level, non-bypassable"]
    B["<b>2. Network</b><br/>VPC, NACL, security groups"]
    C["<b>3. WAF</b><br/>API Gateway, ALB, CloudFront"]
    D["<b>4. KMS encryption</b><br/>per service, per environment"]
    E["<b>5. IAM / IRSA</b><br/>least privilege, no static keys"]
    F["<b>6. GuardDuty</b><br/>threat detection"]
    G["<b>7. Security Hub</b><br/>CIS, FSBP, PCI-DSS, NIST"]
    H["<b>8. Kyverno</b><br/>Kubernetes admission control"]
    I["<b>9. Falco</b><br/>container runtime detection"]
    J["<b>10. AWS Config</b><br/>continuous compliance"]
    K["<b>11. CloudTrail</b><br/>audit of every API call"]

    A --> B --> C --> D --> E --> F --> G --> H --> I --> J --> K

    classDef live fill:#2f855a,stroke:#276749,color:#fff
    classDef partial fill:#c05621,stroke:#9c4221,color:#fff
    classDef absent fill:#e2e8f0,stroke:#a0aec0,color:#4a5568,stroke-dasharray: 5 5

    class B,E,K live
    class A,D partial
    class C,F,G,H,I,J absent
```

| | Layer | Lab status | Why |
|---|-------|-----------|-----|
| 1 | SCP guardrails | **partial** | 7 policies attached; management account is exempt, so nothing is enforced until member accounts exist |
| 2 | Network | **deployed** | VPC, 3 tiers, locked-down defaults, SG chain, NACL, flow logs |
| 3 | WAF | absent | WAFv2 web ACL is ~$5/month + per-rule and per-request charges |
| 4 | KMS | **partial** | AWS-managed keys only; customer-managed keys cost $1/month each |
| 5 | IAM / IRSA | **deployed** | OIDC federation, 4 scoped CI roles, MFA-gated admin role, no static keys |
| 6 | GuardDuty | absent | free for 30 days, then billed per event volume |
| 7 | Security Hub | absent | free for 30 days, then billed per check |
| 8 | Kyverno | absent | requires a Kubernetes cluster; EKS is $73/month |
| 9 | Falco | absent | same |
| 10 | AWS Config | absent | billed per configuration item and per rule evaluation |
| 11 | CloudTrail | **deployed** | organization trail, multi-region, log file validation on |

Policy files for the absent layers are committed and reviewable under
`security/` and `kubernetes/` — they are switched off, not missing.

## Identity and access

```mermaid
flowchart TB
    subgraph humans["Human access"]
        U["IAM user muktha-aws"]
        MFA{"MFA present?"}
        PA["cap-platform-admin<br/>1-hour sessions<br/>+ deny guardrails"]
    end

    subgraph machines["Machine access"]
        GHA["GitHub Actions"]
        OIDC["OIDC federation<br/>no stored secret"]
        R["cap-plan / cap-apply<br/>cap-image-push / cap-prowler"]
    end

    subgraph services["Service access"]
        LR["Lambda execution role<br/>4 DynamoDB actions on 1 table"]
        FR["Flow logs role<br/>3 log actions on 1 group"]
    end

    U --> MFA
    MFA -->|yes| PA
    MFA -->|no| DENY["denied"]
    GHA --> OIDC --> R

    ROOT["Account root"] -.->|"retired — see layer 00"| X["not used for daily work"]

    classDef ok fill:#2f855a,stroke:#276749,color:#fff
    classDef bad fill:#c53030,stroke:#9b2c2c,color:#fff
    classDef gone fill:#e2e8f0,stroke:#a0aec0,color:#4a5568,stroke-dasharray: 4 4
    class PA,R,LR,FR ok
    class DENY bad
    class ROOT,X gone
```

Every execution role names its resources explicitly. The Lambda role, for
example, grants exactly `PutItem`, `GetItem`, `Query` and `Scan` on one table
ARN — not `dynamodb:*` on `*`, and not the `AWSLambdaBasicExecutionRole` managed
policy, which grants `logs:*` across every log group in the account.

## Data protection

```mermaid
graph LR
    subgraph rest["At rest"]
        S3["S3 — SSE-S3 + bucket keys<br/>versioning, TLS-only policy"]
        DDB["DynamoDB — AWS-owned key<br/>PITR enabled"]
        EBS["EBS — encryption by default<br/>account-wide"]
    end

    subgraph transit["In transit"]
        TLS["TLS enforced by bucket policy<br/>aws:SecureTransport = false → Deny"]
        API["API Gateway — HTTPS only"]
    end

    subgraph access["Access"]
        PAB["S3 public access blocked<br/>at the account level"]
        POL["Explicit deny beats<br/>any future allow"]
    end

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    class S3,DDB,EBS,TLS,API,PAB,POL d
```

## Preventive, detective, responsive

```mermaid
graph TB
    subgraph prev["Preventive — stops it happening"]
        P1["SCPs"]
        P2["IAM policies + deny guardrails"]
        P3["Security groups, NACLs"]
        P4["S3 account public access block"]
        P5["Checkov, tfsec, Conftest in CI"]
    end

    subgraph det["Detective — tells you it happened"]
        D1["CloudTrail"]
        D2["VPC flow logs"]
        D3["CloudWatch alarms"]
        D4["Budget alarms"]
        D5["Prowler, drift detection"]
    end

    subgraph resp["Responsive — does something about it"]
        R1["SNS notification"]
        R2["Remediation Lambdas"]
        R3["Incident runbooks"]
    end

    prev -->|"what gets through"| det
    det -->|"what needs action"| resp

    classDef p fill:#2f855a,stroke:#276749,color:#fff
    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef r fill:#c05621,stroke:#9c4221,color:#fff
    class P1,P2,P3,P4,P5 p
    class D1,D2,D3,D4,D5 d
    class R1,R2,R3 r
```

Preventive controls are worth more than detective ones because they do not
depend on anybody reading an alert. But they can only encode what you already
thought of, which is why the detective layer is not optional.

## Blast radius

What an attacker reaches from each starting point, given the controls that are
actually deployed:

```mermaid
flowchart TD
    A1["Compromised<br/>GitHub PR"] --> B1["cap-plan only<br/>read-only, cannot apply"]
    A2["Compromised<br/>main branch"] --> B2["cap-apply<br/>admin, but cannot create<br/>access keys or stop CloudTrail"]
    A3["Compromised<br/>Lambda"] --> B3["4 actions on 1 DynamoDB table"]
    A4["Compromised<br/>IAM user"] --> B4["nothing without MFA"]
    A5["Compromised<br/>root"] --> B5["<b>everything</b><br/>SCPs do not apply<br/>to the management account"]

    classDef small fill:#2f855a,stroke:#276749,color:#fff
    classDef med fill:#c05621,stroke:#9c4221,color:#fff
    classDef total fill:#c53030,stroke:#9b2c2c,color:#fff
    class B1,B3,B4 small
    class B2 med
    class B5 total
```

The red box is the honest conclusion of this whole architecture: in a
single-account deployment, root compromise is unbounded and no guardrail in this
repository changes that. Separating workloads into member accounts is what makes
the SCP layer real, and it is the single highest-value change available.
