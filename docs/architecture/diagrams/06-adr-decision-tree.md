# ADR Decision Tree

> **Navigation:** [Diagram Index](README.md) | [ADR Index and Rationale](../../adr/README.md) | [Decision Guide](../decision-guide.md)

The decision tree is a navigational index over the ADRs: you arrive with a
question, follow the branches, and land on the record that already answered it.
Its purpose is described in full in [the ADR index](../../adr/README.md#why-a-decision-tree)
— this page is the map itself.

## Master tree — start here

```mermaid
flowchart TD
    START(["I need to make a<br/>platform decision"]) --> Q1{"What kind of<br/>decision?"}

    Q1 -->|"How do I provision it?"| IAC["<b>Provisioning</b><br/>ADR-0002, 0004, 0008"]
    Q1 -->|"Where does it live?"| ACC["<b>Account + network</b><br/>ADR-0003, 0013, 0016"]
    Q1 -->|"Who can touch it?"| ID["<b>Identity</b><br/>ADR-0005, 0006, 0014"]
    Q1 -->|"How is it protected?"| SEC["<b>Data protection</b><br/>ADR-0009, 0015"]
    Q1 -->|"How does it ship?"| CICD["<b>Delivery</b><br/>ADR-0011, 0012"]
    Q1 -->|"What runs it?"| COMP["<b>Compute</b><br/>ADR-0010"]

    classDef q fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef a fill:#2f855a,stroke:#276749,color:#fff
    class Q1 q
    class IAC,ACC,ID,SEC,CICD,COMP a
```

## Provisioning: which tool owns this resource?

```mermaid
flowchart TD
    A(["New resource to provision"]) --> B{"Is it foundational?<br/><i>org, accounts, VPC,<br/>IAM, KMS, state</i>"}
    B -->|yes| TF["<b>Terraform</b><br/>ADR-0002"]
    B -->|no| C{"Is it an application<br/>construct?<br/><i>API, function, table,<br/>dashboard</i>"}
    C -->|yes| D{"Does it need a value<br/>Terraform owns?"}
    D -->|yes| SSM["<b>CDK, reading SSM</b><br/>ADR-0008"]
    D -->|no| CDK["<b>CDK</b><br/>ADR-0002"]
    C -->|no| E{"Kubernetes workload?"}
    E -->|yes| HELM["<b>Helm + Kyverno</b><br/>ADR-0011"]
    E -->|no| TF

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef r fill:#2f855a,stroke:#276749,color:#fff
    class B,C,D,E d
    class TF,CDK,SSM,HELM r
```

## Identity: how does this principal authenticate?

```mermaid
flowchart TD
    A(["Something needs<br/>AWS credentials"]) --> B{"Human or machine?"}

    B -->|human| C{"Routine work or<br/>emergency?"}
    C -->|routine| SSO["<b>IAM Identity Center</b><br/>permission set"]
    C -->|emergency| BG["<b>cap-platform-admin</b><br/>MFA-gated, 1h session<br/>ADR-0014"]

    B -->|machine| D{"Running in AWS<br/>or outside it?"}
    D -->|inside AWS| E{"On EKS?"}
    E -->|yes| IRSA["<b>IRSA</b><br/>service account role"]
    E -->|no| ROLE["<b>Execution role</b><br/>named resources only"]
    D -->|outside AWS| F{"GitHub Actions?"}
    F -->|yes| OIDC["<b>OIDC federation</b><br/>ADR-0005"]
    F -->|no| G["<b>Stop.</b><br/>Static keys are not<br/>an approved option"]

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef r fill:#2f855a,stroke:#276749,color:#fff
    classDef stop fill:#c53030,stroke:#9b2c2c,color:#fff
    class B,C,D,E,F d
    class SSO,BG,IRSA,ROLE,OIDC r
    class G stop
```

## Guardrails: preventive or detective?

```mermaid
flowchart TD
    A(["A rule must hold"]) --> B{"Can it be expressed<br/>as an API deny?"}
    B -->|yes| C{"Must it survive a<br/>local admin?"}
    C -->|yes| SCP["<b>Service Control Policy</b><br/>ADR-0006<br/><i>note: management account exempt</i>"]
    C -->|no| IAM["<b>IAM policy</b><br/>or permission boundary"]
    B -->|no| D{"Checkable before<br/>deployment?"}
    D -->|yes| CI["<b>Checkov / tfsec / Conftest</b><br/>ADR-0011"]
    D -->|no| E{"Kubernetes admission?"}
    E -->|yes| KY["<b>Kyverno policy</b>"]
    E -->|no| CFG["<b>Config rule + alarm</b><br/>detective, not preventive"]

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef prev fill:#2f855a,stroke:#276749,color:#fff
    classDef det fill:#c05621,stroke:#9c4221,color:#fff
    class B,C,D,E d
    class SCP,IAM,CI,KY prev
    class CFG det
```

## Encryption: which key?

```mermaid
flowchart TD
    A(["Data needs<br/>encryption at rest"]) --> B{"Regulated data or<br/>production?"}
    B -->|yes| CMK["<b>Customer-managed key</b><br/>rotation on, own key policy<br/>$1/month · ADR-0009"]
    B -->|no| C{"Do you need an<br/>auditable key policy or<br/>independent revocation?"}
    C -->|yes| CMK
    C -->|no| D{"Does the service write<br/>logs to this bucket?<br/><i>CloudTrail, access logs</i>"}
    D -->|yes| S3K["<b>SSE-S3</b><br/>server access logging<br/>cannot use SSE-KMS"]
    D -->|no| AWSK["<b>AWS-managed key</b><br/>free · ADR-0015"]

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef paid fill:#c05621,stroke:#9c4221,color:#fff
    classDef free fill:#2f855a,stroke:#276749,color:#fff
    class B,C,D d
    class CMK paid
    class S3K,AWSK free
```

## Network placement: which subnet tier?

```mermaid
flowchart TD
    A(["Where does this<br/>resource go?"]) --> B{"Must the internet<br/>reach it directly?"}
    B -->|yes| PUB["<b>Public subnet</b><br/>load balancers only"]
    B -->|no| C{"Is it a datastore?"}
    C -->|yes| ISO["<b>Isolated subnet</b><br/>no default route"]
    C -->|no| D{"Does it need<br/>internet egress?"}
    D -->|no| PRIV["<b>Private subnet</b><br/>gateway endpoints only"]
    D -->|yes| E{"Is a NAT gateway<br/>budgeted?"}
    E -->|yes| PRIVNAT["<b>Private subnet</b><br/>+ NAT gateway"]
    E -->|no| F{"Only needs AWS APIs?"}
    F -->|yes| VPCE["<b>Private subnet</b><br/>+ interface endpoints"]
    F -->|no| OUT["<b>Outside the VPC</b><br/>e.g. Lambda · ADR-0016"]

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef r fill:#2f855a,stroke:#276749,color:#fff
    class B,C,D,E,F d
    class PUB,ISO,PRIV,PRIVNAT,VPCE,OUT r
```

## Cost: should this exist in the lab?

The tree that governed every choice in `terraform/lab/`.

```mermaid
flowchart TD
    A(["Component proposed<br/>for the lab"]) --> B{"Free tier or<br/>always free?"}
    B -->|yes| YES["<b>Deploy it</b>"]
    B -->|no| C{"Does it teach something<br/>nothing free can?"}
    C -->|no| DROP["<b>Leave it out</b>"]
    C -->|yes| D{"Under $5/month?"}
    D -->|no| FLAG["<b>Write it, flag it off</b><br/>e.g. enable_nat_gateway"]
    D -->|yes| E{"Can it run bounded<br/>and be torn down?"}
    E -->|yes| TIMED["<b>Deploy, document the cost,</b><br/><b>script the teardown</b>"]
    E -->|no| FLAG

    classDef d fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef yes fill:#2f855a,stroke:#276749,color:#fff
    classDef flag fill:#c05621,stroke:#9c4221,color:#fff
    classDef no fill:#e2e8f0,stroke:#a0aec0,color:#4a5568
    class B,C,D,E d
    class YES,TIMED yes
    class FLAG flag
    class DROP no
```

Every "flag it off" outcome is why `terraform/lab/` has variables like
`enable_nat_gateway` and `enable_interface_endpoints` rather than deleted code:
the production shape stays reviewable in the repository without being billed for.
