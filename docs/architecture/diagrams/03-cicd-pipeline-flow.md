# CI/CD Pipeline Flow

> **Navigation:** [Diagram Index](README.md) | [CI/CD How-To](../../how-to/ci-cd-pipeline.md) | [ADR-0005 OIDC](../../adr/0005-github-oidc-over-static-keys.md) | [ADR-0012 Promotion Gates](../../adr/0012-environment-promotion-gates.md)

## Full pipeline

Twelve workflows, in three bands: everything that runs on a pull request,
everything that runs after merge, and everything that runs on a schedule.

```mermaid
flowchart TB
    Dev(["Developer pushes branch"]) --> PR{{"Pull request opened"}}

    subgraph prchecks["On pull request — must all pass"]
        direction TB
        W00["<b>00 pre-checks</b><br/>gitleaks, commitlint,<br/>file checks, dependency review"]
        W01["<b>01 IaC security</b><br/>Checkov, tfsec, TFLint,<br/>Conftest, Infracost"]
        W02["<b>02 SAST</b><br/>CodeQL, Semgrep, Bandit"]
        W03["<b>03 SCA + SBOM</b><br/>Trivy, Grype, Syft"]
        W04["<b>04 container security</b><br/>Hadolint, Trivy image"]
        W07["<b>07 terraform plan</b><br/>role: cap-plan<br/>plan posted to PR"]
        WCDK["<b>cdk-deploy</b><br/>jest, cdk synth, cdk diff"]
    end

    PR --> prchecks
    prchecks --> Review{{"Review + branch protection"}}
    Review --> Merge(["Merge to main"])

    subgraph postmerge["On merge to main"]
        direction TB
        W08["<b>08 terraform apply</b><br/>role: cap-apply"]
        WCDK2["<b>cdk-deploy</b><br/>deploy stacks in order"]
        W09["<b>09 release</b><br/>semantic release,<br/>SBOM attestation"]
        WPF["<b>platform-foundation</b><br/>management → logging →<br/>security → shared-services"]
    end

    Merge --> postmerge

    subgraph scheduled["Scheduled"]
        direction TB
        W05["<b>05 DAST</b><br/>weekdays 02:00<br/>ZAP baseline + API scan"]
        W06["<b>06 compliance</b><br/>daily 06:00<br/>Prowler, drift detection"]
        W10["<b>10 lab cost guard</b><br/>daily<br/>fail on billable resources"]
    end

    classDef pr fill:#2b6cb0,stroke:#2c5282,color:#fff
    classDef post fill:#2f855a,stroke:#276749,color:#fff
    classDef sched fill:#6b46c1,stroke:#553c9a,color:#fff
    classDef gate fill:#c05621,stroke:#9c4221,color:#fff

    class W00,W01,W02,W03,W04,W07,WCDK pr
    class W08,WCDK2,W09,WPF post
    class W05,W06,W10 sched
    class PR,Review,Merge gate
```

## Promotion gates

Each environment has a different cost of being wrong, so each has a different
gate. These are GitHub *environment* protection rules, enforced by GitHub rather
than by workflow logic — a workflow cannot vote itself past them.

```mermaid
flowchart LR
    M(["Merge to main"]) --> D["<b>dev</b><br/>auto-approve"]
    D --> S["<b>staging</b><br/>1 reviewer"]
    S --> P["<b>prod</b><br/>2 reviewers<br/>+ 60 minute wait"]

    D -->|terraform apply| DA[("dev account")]
    S -->|terraform apply| SA[("staging account")]
    P -->|terraform apply| PA[("prod account")]

    classDef auto fill:#2f855a,stroke:#276749,color:#fff
    classDef one fill:#c05621,stroke:#9c4221,color:#fff
    classDef two fill:#c53030,stroke:#9b2c2c,color:#fff
    class D,DA auto
    class S,SA one
    class P,PA two
```

The 60-minute wait on production is not bureaucracy: it is the window in which
someone notices that staging broke. Without it, a bad change reaches production
before its blast radius is visible.

## How a workflow gets AWS credentials

No secret is ever stored. GitHub mints a short-lived JWT per job; AWS verifies
it against the OIDC provider and returns credentials that expire with the job.

```mermaid
sequenceDiagram
    participant GH as GitHub Actions
    participant OIDC as token.actions.githubusercontent.com
    participant STS as AWS STS
    participant IAM as IAM role
    participant AWS as AWS APIs

    GH->>OIDC: request OIDC token for this job
    OIDC-->>GH: JWT with sub = repo:Mpurushotham/…:ref:refs/heads/main
    GH->>STS: AssumeRoleWithWebIdentity(role, JWT)
    STS->>IAM: validate signature, aud, and sub against trust policy
    alt sub matches the trust condition
        IAM-->>STS: allowed
        STS-->>GH: temporary credentials (expire with the job)
        GH->>AWS: terraform apply
    else sub does not match
        IAM-->>STS: denied
        STS-->>GH: AccessDenied
    end
```

The `sub` claim is what makes this safe. `cap-apply` trusts exactly
`repo:Mpurushotham/Cloud-AWS-Platform-Management:ref:refs/heads/main` with
`StringEquals` — a pull request from a fork cannot produce that claim, so it
cannot reach the apply role no matter what the workflow file says.

## Role-to-workflow map

```mermaid
graph LR
    subgraph roles["IAM roles (created in lab layer 02)"]
        R1["cap-plan<br/><i>ReadOnly + state read</i>"]
        R2["cap-apply<br/><i>Admin + deny guardrails</i>"]
        R3["cap-image-push<br/><i>ECR push, cap-* only</i>"]
        R4["cap-prowler<br/><i>SecurityAudit + ViewOnly</i>"]
    end

    R1 --> WF1["07 terraform plan<br/><i>any branch, any PR</i>"]
    R2 --> WF2["08 terraform apply<br/><i>refs/heads/main only</i>"]
    R2 --> WF5["platform-foundation<br/><i>refs/heads/main only</i>"]
    R3 --> WF3["04 container security<br/><i>refs/heads/main only</i>"]
    R4 --> WF4["06 compliance<br/><i>any branch</i>"]

    classDef ro fill:#2f855a,stroke:#276749,color:#fff
    classDef rw fill:#c53030,stroke:#9b2c2c,color:#fff
    class R1,R4 ro
    class R2,R3 rw
```

## Where each gate can stop a change

```mermaid
flowchart TD
    C["Change"] --> G1{"Secret detected?<br/><i>gitleaks</i>"}
    G1 -->|yes| STOP1["blocked"]
    G1 -->|no| G2{"IaC misconfiguration?<br/><i>Checkov / tfsec</i>"}
    G2 -->|yes| STOP2["blocked"]
    G2 -->|no| G3{"Policy violation?<br/><i>Conftest / OPA</i>"}
    G3 -->|yes| STOP3["blocked"]
    G3 -->|no| G4{"Vulnerable dependency?<br/><i>Trivy / Grype</i>"}
    G4 -->|yes| STOP4["blocked"]
    G4 -->|no| G5{"Plan shows unexpected<br/>destruction or cost?"}
    G5 -->|yes| STOP5["human review"]
    G5 -->|no| G6{"Environment approval"}
    G6 -->|granted| APPLY["apply"]
    G6 -->|denied| STOP6["blocked"]

    classDef stop fill:#c53030,stroke:#9b2c2c,color:#fff
    classDef go fill:#2f855a,stroke:#276749,color:#fff
    class STOP1,STOP2,STOP3,STOP4,STOP5,STOP6 stop
    class APPLY go
```

Shift-left ordering is deliberate: the cheapest checks run first, so a commit
with a leaked secret fails in seconds rather than after a fifteen-minute image
build.
