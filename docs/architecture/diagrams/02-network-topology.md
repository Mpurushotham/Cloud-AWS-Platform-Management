# Network Topology

> **Navigation:** [Diagram Index](README.md) | [Network Layer](../../../terraform/lab/03-network/README.md) | [ADR-0016 No NAT in Lab](../../adr/0016-no-nat-gateway-in-lab.md)

## Lab VPC — as deployed (`<VPC_ID>`)

Three tiers across two AZs, no NAT gateway, no public IPv4 addresses. Private
and isolated subnets reach S3 and DynamoDB through free gateway endpoints and
have no other route off the VPC.

```mermaid
graph TB
    IGW["Internet Gateway"]

    subgraph vpc["VPC 10.10.0.0/16"]
        direction TB

        subgraph pub["Public tier — routes to IGW"]
            PubA["10.10.0.0/24<br/>us-east-1a"]
            PubB["10.10.1.0/24<br/>us-east-1b"]
        end

        subgraph priv["Private tier — no default route"]
            PrivA["10.10.4.0/22<br/>us-east-1a"]
            PrivB["10.10.8.0/22<br/>us-east-1b"]
        end

        subgraph iso["Isolated tier — no default route, ever"]
            IsoA["10.10.100.0/24<br/>us-east-1a"]
            IsoB["10.10.101.0/24<br/>us-east-1b"]
        end

        GWS3["Gateway endpoint<br/><b>S3</b> — free"]
        GWDDB["Gateway endpoint<br/><b>DynamoDB</b> — free"]
    end

    IGW <--> pub
    priv --> GWS3
    priv --> GWDDB
    iso --> GWS3
    iso --> GWDDB

    NAT["NAT Gateway<br/><b>not deployed</b><br/>~$32/mo per AZ"]
    priv -.->|enable_nat_gateway = true| NAT
    NAT -.-> IGW

    classDef public fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef private fill:#2f855a,stroke:#276749,color:#fff
    classDef isolated fill:#c05621,stroke:#9c4221,color:#fff
    classDef free fill:#38a169,stroke:#276749,color:#fff
    classDef off fill:#e2e8f0,stroke:#a0aec0,color:#4a5568,stroke-dasharray: 5 5

    class PubA,PubB public
    class PrivA,PrivB private
    class IsoA,IsoB isolated
    class GWS3,GWDDB free
    class NAT off
```

## What "no NAT" means in practice

```mermaid
flowchart LR
    W["Workload in<br/>private subnet"]

    W -->|reachable| S3["S3"]
    W -->|reachable| DDB["DynamoDB"]
    W -.->|BLOCKED| STS["STS, Secrets Manager,<br/>ECR, CloudWatch"]
    W -.->|BLOCKED| NET["Any internet<br/>destination"]

    classDef ok fill:#2f855a,stroke:#276749,color:#fff
    classDef no fill:#c53030,stroke:#9b2c2c,color:#fff
    class S3,DDB ok
    class STS,NET no
```

This is why the sample Lambda runs **outside** the VPC, and why EKS and ECS are
not part of the lab: managed nodes cannot join a cluster they cannot reach.
Setting `enable_interface_endpoints = true` (~$7.30/month per endpoint per AZ)
restores the blocked paths without a NAT gateway.

## Security group chain

Every rule is a discrete `aws_security_group_rule`. Traffic is authorised by
*source security group*, not by CIDR, so the chain holds no matter how subnets
are renumbered.

```mermaid
graph LR
    NET["Internet"] -->|":443"| ALB["sg-alb"]
    ALB -->|":8080"| APP["sg-app"]
    APP -->|":5432"| DATA["sg-data"]
    APP -->|":443"| AWS["AWS service endpoints"]

    DATA -.->|no egress rules| X["nowhere"]

    classDef sg fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef dead fill:#e2e8f0,stroke:#a0aec0,color:#4a5568,stroke-dasharray: 4 4
    class ALB,APP,DATA sg
    class X dead
```

The data tier has ingress from `sg-app` only and no egress rules at all — a
compromised database cannot initiate an outbound connection.

## Defaults locked down

A new VPC ships with a permissive default security group, NACL and route table.
All three are adopted into Terraform with no rules, so anything launched without
an explicit security group is isolated rather than reachable:

| Default resource | State after apply |
|------------------|-------------------|
| Default security group | no ingress, no egress |
| Default NACL | no allow rules |
| Default (main) route table | no routes |

## Target production VPC

Same shape, three AZs, with the components the lab omits:

```mermaid
graph TB
    subgraph prod["Production VPC 10.30.0.0/16 — 3 AZs"]
        P1["Public × 3<br/>ALB only"]
        P2["Private × 3<br/>EKS nodes, ECS tasks"]
        P3["Isolated × 3<br/>RDS Multi-AZ, ElastiCache"]
        N["NAT Gateway × 3<br/>one per AZ"]
        IE["Interface endpoints × 10<br/>ECR, SSM, Secrets Manager,<br/>STS, Logs, KMS, X-Ray"]
        GW["Gateway endpoints × 2<br/>S3, DynamoDB"]
    end

    P2 --> N --> P1
    P2 --> IE
    P2 --> GW
    P3 --> GW

    classDef t fill:#2b6cb0,stroke:#2c5282,color:#fff
    class P1,P2,P3,N,IE,GW t
```

One NAT gateway per AZ rather than one shared: a shared gateway makes every AZ
depend on the one it lives in, which converts a single-AZ failure into a
total loss of egress.
