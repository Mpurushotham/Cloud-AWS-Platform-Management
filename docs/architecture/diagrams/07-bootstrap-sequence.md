# Bootstrap and State Management

> **Navigation:** [Diagram Index](README.md) | [Lab Setup Runbook](../../how-to/lab-setup-free-tier.md) | [Bootstrap How-To](../../how-to/bootstrap-platform.md) | [ADR-0004 State Backend](../../adr/0004-s3-dynamodb-state-backend.md)

## Lab bootstrap order — as executed

Each layer consumes outputs from the one before it. The ordering is not
stylistic: layer 02 cannot write access logs before layer 01 creates the bucket,
and layer 04 has nothing to hand off until layer 03 exists.

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator
    participant TF as Terraform
    participant AWS as AWS

    Note over Op,AWS: Layer 00 — identity
    Op->>TF: apply 00-identity
    TF->>AWS: create cap-platform-admin (MFA-gated)
    TF->>AWS: password policy, S3 account PAB,<br/>EBS default encryption, IMDSv2 default
    AWS-->>Op: role ARN + profile snippet
    Note over Op: switch CLI to the role,<br/>stop using root

    Note over Op,AWS: Layer 01 — governance
    Op->>TF: import existing organization <ORG_ID>
    Op->>TF: apply 01-governance
    TF->>AWS: enable SCP + tag policy types on root
    TF->>AWS: create 6 OUs
    TF->>AWS: create 7 SCPs, attach to root / Workloads / Prod
    TF->>AWS: org CloudTrail + trail bucket + access-log bucket
    TF->>AWS: budget with actual and forecast alarms
    AWS-->>Op: OU ids, access_logs_bucket_name

    Note over Op,AWS: Layer 02 — bootstrap
    Op->>TF: apply 02-bootstrap (access_log_bucket_name from layer 01)
    TF->>AWS: S3 state bucket + DynamoDB lock table
    TF->>AWS: GitHub OIDC provider
    TF->>AWS: cap-plan, cap-apply, cap-image-push, cap-prowler
    AWS-->>Op: role ARNs + backend config
    Op->>TF: terraform init -migrate-state

    Note over Op,AWS: Layer 03 — network
    Op->>TF: apply 03-network
    TF->>AWS: VPC, 6 subnets, IGW, gateway endpoints
    TF->>AWS: security groups, NACL, flow logs
    TF->>AWS: lock down default SG / NACL / route table

    Note over Op,AWS: Layer 04 — workload
    Op->>TF: apply 04-workload
    TF->>AWS: DynamoDB, Lambda, HTTP API
    TF->>AWS: log groups, alarms, dashboard, SNS
    TF->>AWS: publish /cap/lab/* to SSM
    AWS-->>Op: API endpoint
    Op->>AWS: curl /health → 200
```

## The bootstrap chicken-and-egg

Layer 02 creates the very bucket that layer 02 wants to store its state in.

```mermaid
flowchart LR
    A["Local backend<br/><i>terraform.tfstate on disk</i>"] --> B["apply 02-bootstrap"]
    B --> C["S3 bucket +<br/>DynamoDB table exist"]
    C --> D["write backend.tf"]
    D --> E["terraform init<br/>-migrate-state"]
    E --> F["state now lives in S3"]

    classDef s fill:#2b6cb0,stroke:#2c5282,color:#fff
    class A,B,C,D,E,F s
```

Every other layer skips straight to the S3 backend, because by the time it runs
the bucket already exists.

## State locking

```mermaid
sequenceDiagram
    participant A as Engineer A
    participant B as Engineer B
    participant DDB as DynamoDB lock table
    participant S3 as S3 state bucket

    A->>DDB: PutItem(LockID) with condition: not exists
    DDB-->>A: acquired
    A->>S3: read state
    B->>DDB: PutItem(LockID) with condition: not exists
    DDB-->>B: ConditionalCheckFailed
    B-->>B: "Error acquiring the state lock"
    A->>S3: write new state
    A->>DDB: DeleteItem(LockID)
    B->>DDB: PutItem(LockID)
    DDB-->>B: acquired
```

The conditional write is what makes this safe — two applies cannot both believe
they hold the lock. Without it, concurrent applies interleave writes and produce
a state file describing infrastructure that never existed.

## Recovering from a corrupted state file

Bucket versioning exists for exactly this.

```mermaid
flowchart TD
    A["State is wrong"] --> B{"Lock stuck?"}
    B -->|yes| C["terraform force-unlock LOCK_ID<br/><i>only after confirming no apply is running</i>"]
    B -->|no| D{"State corrupted<br/>or truncated?"}
    D -->|yes| E["aws s3api list-object-versions<br/>--bucket cap-lab-tfstate-…<br/>--prefix layer/terraform.tfstate"]
    E --> F["copy the last good version<br/>over the current one"]
    D -->|no| G{"Resource drifted<br/>outside Terraform?"}
    G -->|yes| H["terraform import<br/>or terraform apply -refresh-only"]
    G -->|no| I["terraform plan<br/>and read it carefully"]

    classDef a fill:#c05621,stroke:#9c4221,color:#fff
    classDef f fill:#2f855a,stroke:#276749,color:#fff
    class C,F,H a
    class I f
```

`prevent_destroy` on the state bucket and lock table means Terraform refuses to
delete them even when told to — the one class of mistake that is genuinely
unrecoverable.

## State key layout

```
s3://cap-lab-tfstate-<ACCOUNT_ID>/
├── lab/identity/terraform.tfstate
├── lab/governance/terraform.tfstate
├── lab/bootstrap/terraform.tfstate
├── lab/network/terraform.tfstate
└── lab/workload/terraform.tfstate
```

One state file per layer, not one for everything. A single state means every
apply takes a lock on every resource, a corrupt file loses the whole platform,
and the blast radius of `terraform destroy` is the entire account.
