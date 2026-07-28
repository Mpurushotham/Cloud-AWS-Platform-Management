# Request Path and Terraform → CDK Handoff

> **Navigation:** [Diagram Index](README.md) | [Workload Layer](../../../terraform/lab/04-workload/README.md) | [ADR-0008 SSM Handoff](../../adr/0008-ssm-parameter-store-handoff.md)

## Deployed request path

The lab's sample API, as it actually runs. Every hop is inside the free tier.

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant AG as API Gateway<br/>HTTP API
    participant L as Lambda<br/>cap-lab-api
    participant D as DynamoDB<br/>cap-lab-items
    participant CW as CloudWatch
    participant X as X-Ray

    C->>AG: POST /items {"name":"first"}
    AG->>AG: match route, apply throttle<br/>(5 req/s, burst 10)
    AG->>CW: access log entry
    AG->>L: invoke (AWS_PROXY, payload v2.0)
    activate L
    L->>X: begin trace segment
    L->>L: validate body
    L->>D: PutItem (TTL +7 days)
    D-->>L: ok
    L->>CW: structured JSON log line
    L->>X: end segment
    L-->>AG: 201 + item
    deactivate L
    AG-->>C: 201 {"pk":"…","name":"first"}
```

Failure paths are explicit rather than incidental:

| Condition | Response | Why |
|-----------|----------|-----|
| Body is not JSON | `400 body must be valid JSON` | caller error, safe to describe |
| `name` missing | `400 field 'name' is required` | caller error, safe to describe |
| Route not registered | `404` from API Gateway | never reaches Lambda, never billed |
| DynamoDB error | `502 upstream service error` | AWS error code logged, not returned |
| Unhandled exception | `500 internal error` | stack trace logged, never returned |

Returning the AWS error code to the caller would disclose table names and ARNs,
so the code goes to CloudWatch and the caller gets a generic message with a
request ID.

## Cost guardrails on this path

```mermaid
flowchart LR
    F["Flood of requests"] --> T1["API Gateway throttle<br/>5/s steady, 10 burst"]
    T1 --> T2["Lambda reserved<br/>concurrency = 5"]
    T2 --> T3["DynamoDB on-demand<br/>+ 7-day TTL"]
    T3 --> A["CloudWatch alarm<br/>>1000 req / 5 min"]
    A --> B["Budget alarm<br/>10% actual, 100% forecast"]

    classDef guard fill:#c05621,stroke:#9c4221,color:#fff
    class T1,T2,T3,A,B guard
```

Five independent limits. Any one of them failing still leaves four in the path —
which is the point, because the API is deliberately unauthenticated so that
`curl` can demonstrate it.

## Terraform → CDK handoff

Terraform owns foundational resources; CDK owns application stacks. They are
joined through SSM Parameter Store rather than shared state or CloudFormation
exports.

```mermaid
flowchart LR
    subgraph tf["Terraform (foundation)"]
        TF1["VPC, subnets, SGs"]
        TF2["DynamoDB table"]
        TF3["HTTP API, Lambda"]
    end

    SSM[("SSM Parameter Store<br/>/cap/lab/*")]

    subgraph cdk["CDK (application)"]
        C1["NetworkStack"]
        C2["SecurityStack"]
        C3["PlatformStack"]
        C4["DataStack"]
        C5["ApiStack"]
        C6["ObservabilityStack"]
    end

    TF1 -->|writes| SSM
    TF2 -->|writes| SSM
    TF3 -->|writes| SSM
    SSM -->|reads at synth| C1
    C1 --> C2 --> C3 --> C4 --> C5 --> C6

    classDef t fill:#7c3aed,stroke:#5b21b6,color:#fff
    classDef s fill:#c05621,stroke:#9c4221,color:#fff
    classDef c fill:#2b6cb0,stroke:#2c5282,color:#fff
    class TF1,TF2,TF3 t
    class SSM s
    class C1,C2,C3,C4,C5,C6 c
```

### Why SSM and not the alternatives

| Approach | Why it was rejected |
|----------|---------------------|
| CDK reads Terraform remote state | CDK would need read access to the state bucket, and state contains every resource attribute in the account — far more than the handful of IDs it needs |
| CloudFormation exports | An exported value cannot be changed or deleted while any stack imports it, which produces stacks that cannot be updated or deleted |
| Hard-coded IDs in `cdk.json` | Silently wrong after any Terraform change that replaces a resource |
| SSM Parameter Store | Loosely coupled, versioned, IAM-scopable per parameter path, free at Standard tier |

Parameters currently published by layer 04:

```
/cap/lab/api/id              /cap/lab/table/name
/cap/lab/api/endpoint        /cap/lab/table/arn
/cap/lab/api/execution-arn   /cap/lab/function/name
/cap/lab/alarms/topic-arn    /cap/lab/function/arn
```

## CDK stack dependency order

Enforced with `addDependency`, not by declaration order — CDK synthesises stacks
in whatever order it likes unless told otherwise.

```mermaid
graph LR
    N["NetworkStack<br/>VPC, subnets"] --> S["SecurityStack<br/>KMS, IAM, WAF"]
    S --> P["PlatformStack<br/>EKS, ECS"]
    P --> D["DataStack<br/>RDS, ElastiCache"]
    D --> A["ApiStack<br/>API Gateway, ALB"]
    A --> O["ObservabilityStack<br/>dashboards, alarms"]

    classDef st fill:#2b6cb0,stroke:#2c5282,color:#fff
    class N,S,P,D,A,O st
```

Security precedes platform because KMS keys must exist before anything asks to
be encrypted with them; observability comes last because it references the ARNs
of everything before it.
