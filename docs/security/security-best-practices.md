# Security Best Practices

> **Navigation:** [Docs Index](../README.md) | [Known Issues](known-issues.md) | [Security Layers Diagram](../architecture/diagrams/05-security-layers.md) | [ADR Index](../adr/README.md)

What this platform enforces, how it is enforced, and — where it is not enforced
— what would be required. Every row states its current status honestly; a
control listed as implemented is one you can verify with the command given.

---

## 1. Identity and access

### Never use the account root user

Root is outside IAM: no policy constrains it, no permission boundary applies, and
in the management account **no Service Control Policy applies either**. Its
compromise cannot be contained by anything in this repository.

| Practice | Status | Where |
|----------|--------|-------|
| No root access keys | **enforced** | verified by `scripts/lab-verify.sh` (CIS 1.4) |
| MFA on root | **enabled** | `AccountMFAEnabled = 1` |
| Root used only for tasks AWS permits nowhere else | **discipline** | [ADR-0014](../adr/0014-eliminate-root-access-keys.md) |
| Alarm on root usage | **outstanding** | [known issue](known-issues.md) |

```bash
aws iam get-account-summary --query 'SummaryMap.{RootKeys:AccountAccessKeysPresent,MFA:AccountMFAEnabled}'
```

### Prefer roles to users, and short sessions to long ones

| Practice | Status | Where |
|----------|--------|-------|
| MFA-gated admin role, 1-hour sessions | **implemented** | `cap-platform-admin` |
| No long-lived keys in CI | **implemented** | OIDC federation, [ADR-0005](../adr/0005-github-oidc-over-static-keys.md) |
| Password policy ≥ 14 chars, 90-day rotation | **implemented** | CIS 1.8/1.9 |
| IAM Identity Center for human access | **not deployed** | requires member accounts |

### Least privilege means naming resources

An execution role should enumerate the actions it performs on the resources it
touches. The Lambda role in this repository grants exactly four DynamoDB actions
on one table ARN:

```hcl
statement {
  actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
  resources = [aws_dynamodb_table.items.arn]
}
```

It deliberately does **not** attach `AWSLambdaBasicExecutionRole`, which grants
`logs:*` across every log group in the account. Writing the three log actions
against one named group is a few extra lines and a materially smaller grant.

### Constrain service principals against the confused deputy

Any trust policy naming a service principal should carry `aws:SourceArn` or
`aws:SourceAccount`. Without it, another account can induce the service to
assume your role on its behalf:

```hcl
principals {
  type        = "Service"
  identifiers = ["vpc-flow-logs.amazonaws.com"]
}
condition {
  test     = "StringEquals"
  variable = "aws:SourceAccount"
  values   = [data.aws_caller_identity.current.account_id]
}
```

Applied to the flow-logs role, the Lambda execution role, the SNS topic policy
and both CloudTrail bucket statements.

### Explicit deny beats any future allow

`cap-apply` holds `AdministratorAccess` because Terraform genuinely needs it. It
is contained by unconditional denies rather than by an enumerated allow-list,
because an explicit deny wins over any allow — including one added later:

```hcl
statement {
  sid       = "NoLongLivedCredentials"
  effect    = "Deny"
  actions   = ["iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:CreateUser"]
  resources = ["*"]
}
```

The role that exists to remove static credentials cannot mint them.

---

## 2. Preventive guardrails

| Practice | Status | Notes |
|----------|--------|-------|
| SCPs attached at Root and OU level | **implemented** | 7 policies, [ADR-0006](../adr/0006-scps-as-preventive-guardrails.md) |
| SCPs actually enforcing | **not in the lab** | management account is exempt |
| S3 public access blocked account-wide | **implemented** | CIS 2.1.4 |
| EBS encryption by default | **implemented** | CIS 2.2.1 |
| IMDSv2 required by default | **implemented** | region-level default |

Two things to know before extending SCPs:

**The management account is exempt, always.** There is no configuration that
changes this. Guardrails only become real once workloads live in member accounts.

**A target accepts 5 SCPs, and `FullAWSAccess` uses one.** The four root
attachments sit exactly at quota; a fifth guardrail must be merged into an
existing document.

---

## 3. Data protection

| Practice | Status | Notes |
|----------|--------|-------|
| Encryption at rest everywhere | **implemented** | see below for which keys |
| TLS enforced by bucket policy | **implemented** | `aws:SecureTransport = false` → Deny |
| Versioning on all buckets | **implemented** | recovery from bad writes |
| Public access blocked per bucket and account-wide | **implemented** | |
| Server access logging | **implemented** | central log bucket |
| Lifecycle expiry | **implemented** | 30 days logs, 90 days state versions |
| Customer-managed KMS keys | **not in the lab** | $1/month each, [ADR-0015](../adr/0015-lab-encryption-tradeoffs.md) |

Two constraints worth internalising:

- **S3 server access logging cannot deliver into an SSE-KMS bucket.** The
  access-log bucket uses SSE-S3 in production as well. This is an AWS
  limitation, not a cost decision.
- **Terraform state contains resource attributes in plaintext**, which can
  include generated passwords. It deserves the same protection as a secrets
  store.

### The TLS-only bucket policy

Every bucket carries this. It is four lines and closes a real gap — bucket
encryption protects data at rest, not in transit:

```hcl
statement {
  sid     = "DenyNonTLS"
  effect  = "Deny"
  actions = ["s3:*"]
  principals { type = "AWS", identifiers = ["*"] }
  resources = [bucket.arn, "${bucket.arn}/*"]
  condition {
    test     = "Bool"
    variable = "aws:SecureTransport"
    values   = ["false"]
  }
}
```

---

## 4. Network

| Practice | Status | Notes |
|----------|--------|-------|
| Three-tier subnet separation | **implemented** | public / private / isolated |
| Databases in subnets with no default route | **implemented** | isolated tier |
| Default SG, NACL and route table locked down | **implemented** | adopted with no rules |
| Security group rules as discrete resources | **implemented** | never inline blocks |
| Rules reference source security groups, not CIDRs | **implemented** | |
| VPC flow logs | **implemented** | CloudWatch, 7-day retention |
| Private subnet egress | **not in the lab** | [ADR-0016](../adr/0016-no-nat-gateway-in-lab.md) |
| WAF | **not deployed** | ~$5/month plus per-request |

### Why security group rules are separate resources

An inline `ingress` block is authoritative: Terraform removes any rule it does
not know about. When someone adds an emergency rule during an incident, the next
apply silently deletes it. Discrete `aws_security_group_rule` resources do not
have this behaviour.

```hcl
# Correct
resource "aws_security_group_rule" "app_ingress_alb" {
  security_group_id        = aws_security_group.app.id
  type                     = "ingress"
  source_security_group_id = aws_security_group.alb.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
}
```

Referencing the *source security group* rather than a CIDR means the rule stays
correct when subnets are renumbered, and expresses the actual intent: "traffic
from the load balancer", not "traffic from 10.10.0.0/22".

### Lock down the defaults

A new VPC ships with a permissive default security group, NACL and route table.
Adopt all three into Terraform with no rules, so anything launched without an
explicit security group is isolated rather than reachable:

```hcl
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # no ingress, no egress — intentional deny-all
}
```

---

## 5. Detection and audit

| Practice | Status | Notes |
|----------|--------|-------|
| Organization CloudTrail, multi-region | **implemented** | management events |
| Log file validation | **implemented** | detects tampering |
| CloudTrail deletion blocked by SCP and IAM | **implemented** | both layers |
| VPC flow logs | **implemented** | |
| Budget alarms — actual and forecast | **implemented** | |
| Application alarms | **implemented** | errors, throttles, 5xx, volume |
| GuardDuty | **not deployed** | 30-day trial, then billed |
| Security Hub | **not deployed** | 30-day trial, then billed |
| AWS Config | **not deployed** | billed per item and evaluation |

Forecast budget alarms matter more than actual ones: an actual alarm tells you
money is already spent, a forecast alarm tells you before it is.

### Set log retention explicitly

A log group created implicitly by Lambda or API Gateway defaults to **never
expire** — a cost leak and a data-retention problem. Declare the group in
Terraform and make the function depend on it:

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "api" {
  depends_on = [aws_cloudwatch_log_group.lambda]
}
```

---

## 6. Application

| Practice | Status | Notes |
|----------|--------|-------|
| Errors logged, never returned to callers | **implemented** | see below |
| Input validated before use | **implemented** | |
| Throttling and concurrency caps | **implemented** | |
| Structured JSON logging | **implemented** | queryable in Logs Insights |
| Distributed tracing | **implemented** | X-Ray, first 100k traces free |
| Authentication on the sample API | **absent** | [known issue](known-issues.md) |

An AWS error code returned to a caller discloses table names and ARNs. Log the
code with a request ID; return a generic message:

```python
except ClientError as exc:
    _log("error", "aws call failed",
         code=exc.response["Error"]["Code"],
         request_id=context.aws_request_id)
    return _response(502, {"error": "upstream service error"})
```

---

## 7. Supply chain

| Practice | Status | Notes |
|----------|--------|-------|
| Secret scanning on every PR | **implemented** | gitleaks |
| IaC scanning | **implemented** | Checkov, tfsec, TFLint |
| Custom policy | **implemented** | Conftest / OPA |
| SAST | **implemented** | CodeQL, Semgrep, Bandit |
| Dependency and container scanning | **implemented** | Trivy, Grype |
| SBOM generation | **implemented** | Syft |
| Image deletion denied to CI | **implemented** | releases are immutable |
| Actions pinned to commit SHAs | **outstanding** | [known issue](known-issues.md) |
| Provider versions pinned | **implemented** | `aws ~> 5.0`, `terraform ~> 1.9` |

---

## Benchmark mapping

Controls implemented in this repository, against CIS AWS Foundations Benchmark
v3.0 and AWS Foundational Security Best Practices:

| Control | Requirement | Status |
|---------|-------------|--------|
| CIS 1.4 | No root access keys | **pass** |
| CIS 1.5 | MFA on root | **pass** |
| CIS 1.8 | Password length ≥ 14 | **pass** |
| CIS 1.9 | Password reuse prevention | **pass** (24) |
| CIS 2.1.1 | S3 encryption at rest | **pass** |
| CIS 2.1.2 | S3 TLS-only policy | **pass** |
| CIS 2.1.4 | S3 public access blocked | **pass** |
| CIS 2.2.1 | EBS encryption by default | **pass** |
| CIS 3.1 | CloudTrail enabled in all regions | **pass** |
| CIS 3.2 | Log file validation | **pass** |
| CIS 3.5 | VPC flow logs | **pass** |
| CIS 3.7 | CloudTrail encrypted with KMS | **gap** — SSE-S3, [ADR-0015](../adr/0015-lab-encryption-tradeoffs.md) |
| CIS 3.8 | KMS key rotation | **n/a** — no customer-managed keys |
| CIS 4.x | Log metric filters and alarms | **gap** — trail delivers to S3 only |
| CIS 5.1 | NACLs deny unrestricted ingress | **pass** |
| CIS 5.3 | Default SG restricts all traffic | **pass** |
| CIS 5.4 | VPC peering least access | **n/a** |
| FSBP IAM.6 | Hardware MFA for root | **partial** — MFA enabled, type unverified |
| FSBP EC2.8 | IMDSv2 required | **pass** — region default |
| FSBP Lambda.2 | Supported runtime | **pass** — Python 3.12 |

Verify with:

```bash
./scripts/lab-verify.sh
```

Prowler runs the full benchmark daily via `06-compliance.yml` using the
`cap-prowler` role.

---

## Checklist for a new component

1. Does every IAM statement name its resources, or is there a `*`?
2. Does every service-principal trust policy carry `aws:SourceArn` or
   `aws:SourceAccount`?
3. Is the data encrypted at rest, and is the key choice deliberate?
4. Is there a TLS-only policy on anything storing data?
5. Is log retention set explicitly?
6. Are security group rules discrete resources referencing source groups?
7. Is there a concurrency, rate or size limit bounding worst-case cost?
8. Do errors get logged rather than returned?
9. Is there an alarm that fires when this breaks?
10. If this deviates from a standard, is there an ADR saying so?
