# Organization Topology

> **Navigation:** [Diagram Index](README.md) | [Architecture Overview](../overview.md) | [Governance Layer](../../../terraform/lab/01-governance/README.md) | [ADR-0003](../../adr/0003-multi-account-landing-zone.md)

## Target topology — multi-account

The design `terraform/environments/` implements. Each account is a hard security
and blast-radius boundary; OUs are the unit that Service Control Policies attach
to.

```mermaid
graph TD
    Root["Root<br/><i>Management account</i><br/>Organizations, SCPs, billing"]

    Root --> Core["<b>Core OU</b>"]
    Root --> Infra["<b>Infrastructure OU</b>"]
    Root --> Work["<b>Workloads OU</b>"]
    Root --> Sand["<b>Sandbox OU</b>"]

    Core --> LZ["Landing Zone<br/>Control Tower, Account Factory"]
    Core --> Sec["Security<br/>Security Hub aggregator<br/>GuardDuty master, Identity Center"]
    Core --> Log["Logging<br/>CloudTrail org trail<br/>Config aggregator, audit S3"]

    Infra --> Shared["Shared Services<br/>ECR, Route53, ACM<br/>Transit Gateway, RAM"]

    Work --> NonProd["<b>Non-Prod OU</b>"]
    Work --> Prod["<b>Prod OU</b>"]

    NonProd --> Dev["Dev<br/>10.10.0.0/16"]
    NonProd --> Test["Test<br/>10.11.0.0/16"]
    NonProd --> Stage["Staging<br/>10.20.0.0/16"]

    Prod --> Production["Production<br/>10.30.0.0/16"]

    Sand --> Sandbox["Sandbox<br/>10.90.0.0/16"]

    classDef mgmt fill:#4a5568,stroke:#2d3748,color:#fff
    classDef ou fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef acct fill:#2f855a,stroke:#276749,color:#fff
    classDef prodacct fill:#c05621,stroke:#9c4221,color:#fff

    class Root mgmt
    class Core,Infra,Work,Sand,NonProd,Prod ou
    class LZ,Sec,Log,Shared,Dev,Test,Stage,Sandbox acct
    class Production prodacct
```

## Lab topology — single account, as deployed

What actually exists in account `<ACCOUNT_ID>` today. The OU tree is real and
identical in shape; there are no member accounts to place inside it, so all
resources live in the management account.

```mermaid
graph TD
    Root["Root <ROOT_ID><br/><i><ORG_ID></i>"]
    Mgmt["<b>Management account <ACCOUNT_ID></b><br/>every lab resource lives here"]

    Root --> Core["Core OU<br/><OU_CORE>"]
    Root --> Infra["Infrastructure OU<br/><OU_INFRASTRUCTURE>"]
    Root --> Work["Workloads OU<br/><OU_WORKLOADS>"]
    Root --> Sand["Sandbox OU<br/><OU_SANDBOX>"]

    Work --> NonProd["Non-Prod OU<br/><OU_NON_PROD>"]
    Work --> Prod["Prod OU<br/><OU_PROD>"]

    Core -.->|empty| E1(( ))
    Infra -.->|empty| E2(( ))
    NonProd -.->|empty| E3(( ))
    Prod -.->|empty| E4(( ))
    Sand -.->|empty| E5(( ))

    Root ==> Mgmt

    classDef mgmt fill:#4a5568,stroke:#2d3748,color:#fff
    classDef ou fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef empty fill:#e2e8f0,stroke:#a0aec0,color:#4a5568,stroke-dasharray: 4 4
    classDef live fill:#2f855a,stroke:#276749,color:#fff

    class Root mgmt
    class Core,Infra,Work,Sand,NonProd,Prod ou
    class E1,E2,E3,E4,E5 empty
    class Mgmt live
```

## SCP attachment and its one important limitation

```mermaid
graph LR
    subgraph attached["Attached to Root"]
        S1["cap-deny-root-user"]
        S2["cap-deny-delete-cloudtrail"]
        S3["cap-deny-public-s3"]
        S4["cap-deny-disable-guardduty"]
    end

    subgraph workloads["Attached to Workloads OU"]
        S5["cap-require-encryption"]
        S6["cap-deny-region-restriction"]
    end

    subgraph prodou["Attached to Prod OU"]
        S7["cap-require-mfa"]
    end

    attached --> MA["Management account<br/><b>EXEMPT — enforces nothing</b>"]
    attached --> MEM["Member accounts<br/><b>enforced</b>"]
    workloads --> MEM
    prodou --> MEM

    classDef exempt fill:#c53030,stroke:#9b2c2c,color:#fff
    classDef enforced fill:#2f855a,stroke:#276749,color:#fff
    class MA exempt
    class MEM enforced
```

**AWS exempts the Organizations management account from every SCP, without
exception.** In the lab every resource lives in that account, so the seven
policies are attached and reviewable but restrict nothing today. They begin
enforcing the moment member accounts exist. This is a property of AWS, not a
shortcut — see [ADR-0013](../../adr/0013-single-account-lab-profile.md).

A second consequence: the `cap-deny-root-user` policy cannot protect the very
account whose root user you are most likely to use. That gap is why
[layer 00](../../../terraform/lab/00-identity/README.md) exists.

## Root SCP quota

A target accepts at most 5 SCPs and AWS-managed `FullAWSAccess` occupies one, so
the four root attachments sit exactly at quota. A fifth root-level guardrail
must be merged into an existing policy document rather than attached separately.
