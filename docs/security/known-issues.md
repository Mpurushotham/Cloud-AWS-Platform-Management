# Known Issues

> **Navigation:** [Security Best Practices](security-best-practices.md) | [Docs Index](../README.md) | [ADR Index](../adr/README.md)

Defects and accepted risks in this repository, with their current status. An
issue leaves this page only when it is fixed or formally accepted in an ADR.

Findings marked **FIXED** were found and repaired while building the lab
profile; they are retained because the reasoning is useful.

---

## FIXED — 51 Terraform files could not be parsed

**Severity:** blocking

`terraform/environments/*/variables.tf` and 29 module files used semicolons to
separate arguments inside single-line blocks:

```hcl
variable "aws_region" { description = "AWS region"; type = string; default = "us-east-1" }
```

HCL does not accept `;` as a separator, and a single-line block may contain only
one argument. Every affected directory failed at parse time, so none of the
environments or modules could be planned, let alone applied. `terraform fmt`
reported the errors but nothing in CI ran `fmt` as a blocking check.

**Fixed:** all blocks expanded to multi-line form; `terraform fmt -check
-recursive` now passes across the whole tree. A blocking `terraform fmt -check`
step was added to `00-pre-checks.yml`.

---

## FIXED — `terraform/bootstrap` could never apply

**Severity:** blocking

`terraform/bootstrap/oidc.tf` tried to create the GitHub OIDC provider only if
it did not already exist:

```hcl
data "aws_iam_openid_connect_provider" "github" { url = "…" }

resource "aws_iam_openid_connect_provider" "github" {
  count = length(data.aws_iam_openid_connect_provider.github.arn) > 0 ? 0 : 1
  …
}
```

A Terraform data source that matches nothing raises an error; it does not return
an empty value. In an account with no provider — precisely the case this code
branches on — the data source fails during plan and `count` is never evaluated.
The condition can only be false in a situation it can never reach.

**Fixed in the lab layer:** `terraform/lab/02-bootstrap/oidc.tf` replaces the
inference with an explicit `create_oidc_provider` boolean. See
[ADR-0005](../adr/0005-github-oidc-over-static-keys.md).

**Outstanding:** `terraform/bootstrap/` itself still contains the original
pattern. It is superseded by the lab layer for single-account use but would need
the same fix before being used against a real logging account.

---

## FIXED — `modules/vpc` produced overlapping subnet CIDRs at the default AZ count

**Severity:** blocking for that module

`terraform/modules/vpc/subnets.tf` used these offsets:

| Tier | Expression | Result for `10.10.0.0/16`, `az_count = 3` |
|------|-----------|-------------------------------------------|
| public | `cidrsubnet(cidr, 4, i)` | `10.10.0.0/20`, `10.10.16.0/20`, `10.10.32.0/20` |
| private | `cidrsubnet(cidr, 2, i+1)` | `10.10.64.0/18`, `10.10.128.0/18`, **`10.10.192.0/18`** |
| isolated | `cidrsubnet(cidr, 4, i+12)` | **`10.10.192.0/20`**, `10.10.208.0/20`, `10.10.224.0/20` |

All three isolated subnets fall inside `private[2]`, so AWS rejects the
overlapping CIDR part-way through the apply, leaving a half-built VPC.

The failure appears at **`az_count = 3`** — which is the module default and what
`dev`, `staging` and `prod` all pass. At `az_count = 2` the private tier stops at
`10.10.128.0/18` and the ranges happen not to collide, so the bug is invisible in
a two-AZ test. The file's comments also described `/24` and `/22` sizes that the
expressions did not produce.

**Fixed:** offsets changed to `8,i` / `6,i+1` / `8,i+100`, which are disjoint for
every `az_count` up to 3. A `precondition` now asserts non-overlap by converting
each subnet to a half-open interval in /24 units and testing pairwise — string
comparison would not catch containment, which is what the original bug was.

The same arithmetic is used by `terraform/lab/03-network`, where it is deployed
and verified.

---

## FIXED — `require-encryption` SCP denied AWS service log delivery

**Severity:** high if attached broadly

`security/scps/require-encryption.json` contains:

```json
{
  "Sid": "DenyUnencryptedS3Uploads",
  "Effect": "Deny",
  "Action": "s3:PutObject",
  "Condition": { "StringNotEquals": { "s3:x-amz-server-side-encryption": "aws:kms" } }
}
```

The condition tests a *request header*. Bucket default encryption does not set
one, so any writer relying on it is denied — including CloudTrail, AWS Config,
ELB access logs, VPC flow logs and S3 server access logging. Attaching this to an
OU containing a logging account silently stops audit log delivery, which is the
worst possible thing to break quietly.

**Fixed:** a `Null` condition now scopes the deny to requests that actually carry
the header, and `AES256` is accepted alongside `aws:kms` since some AWS services
cannot write with SSE-KMS at all:

```json
"Condition": {
  "StringNotEquals": { "s3:x-amz-server-side-encryption": ["aws:kms", "AES256"] },
  "Null":            { "s3:x-amz-server-side-encryption": "false" }
}
```

A request with no header is no longer denied, so service log delivery relying on
bucket default encryption works. A request that explicitly asks for something
else — or for no encryption — still fails.

**Residual gap:** this no longer forces encryption on writers that omit the
header. Bucket default encryption (mandatory on every bucket here) covers that
case, and Checkov enforces it at plan time. Preventing unencrypted objects
entirely requires a bucket policy per bucket, not an SCP.

---

## FIXED — the cost guard was the only thing costing money

**Severity:** low in absolute terms, instructive out of proportion to the amount

`scripts/lab-verify.sh` called `aws ce get-cost-and-usage` to report
month-to-date spend. The **Cost Explorer API bills $0.01 per request**.

Month-to-date spend on the lab account, broken down:

| Service | Cost |
|---------|------|
| AWS Cost Explorer | **$0.02** |
| DynamoDB | $0.00000175 |
| S3 | $0.0000007028 |
| CloudTrail, Lambda, API Gateway, KMS, SNS, CloudWatch | $0 |

Every deployed resource together came to less than a thousandth of a cent. The
only measurable charge was the script asserting that nothing was charging.

Worse, `10-lab-cost-guard.yml` runs that script on a daily schedule and on every
pull request touching `terraform/lab/`, so it would have accrued roughly
**$0.30/month and rising** — making the cost guard the largest line item in a
lab budgeted at $0, and the direct cause of the drift it exists to detect.

**Fixed:** the Cost Explorer query is now opt-in behind
`LAB_VERIFY_COST_QUERY=1` and skipped by default. The budget alarms from layer
01 already provide the real guardrail — they notify at 10% actual and 100%
forecast and cost nothing per evaluation.

**The general lesson:** a monitoring control is part of the system it monitors,
and its own cost, permissions and failure modes count. This one was found only
because the account was checked *after* the guard had been running, not because
the guard reported it — it had no way to see itself.

---

## OPEN — the sample API is unauthenticated

**Severity:** accepted for the lab

`terraform/lab/04-workload` exposes `GET /health`, `GET /items` and
`POST /items` with no authorisation, so anyone who learns the endpoint can write
to the DynamoDB table.

**Why:** `curl` demonstrates the full request path with no credential setup,
which is the layer's purpose.

**Mitigations in place:** API Gateway throttling (5 req/s, burst 10), Lambda
reserved concurrency of 5, DynamoDB TTL of 7 days, a CloudWatch alarm above
1,000 requests per 5 minutes, and a budget alarm. Worst-case cost from a flood
is bounded at a few dollars.

**Fix for any real use:** set `authorization_type = "AWS_IAM"` on the routes and
sign requests with SigV4, or add a JWT authoriser.

---

## OPEN — SCPs enforce nothing in the lab

**Severity:** accepted, architectural

AWS exempts the Organizations management account from every SCP. All lab
resources live in the management account, so the seven attached policies
restrict nothing.

**Accepted in** [ADR-0013](../adr/0013-single-account-lab-profile.md).
**Resolved by** creating real member accounts and moving workloads into them.

---

## OPEN — no customer-managed KMS keys in the lab

**Severity:** accepted, cost-driven

AWS-managed and AWS-owned keys are used throughout. Data is encrypted, but there
is no editable key policy, no independent revocation and weaker attribution.

**Accepted in** [ADR-0015](../adr/0015-lab-encryption-tradeoffs.md).
**Resolved by** setting `state_encryption = "aws:kms"` and adding per-service
keys — $1/month each.

---

## OPEN — no CloudWatch alarm on root account usage

**Severity:** medium

[ADR-0014](../adr/0014-eliminate-root-access-keys.md) makes root non-use a
discipline rather than a technical control, and nothing currently detects a
violation. The standard control is a metric filter on the CloudTrail log group
matching `$.userIdentity.type = "Root"`, with an alarm to SNS.

**Blocked by:** the organization trail delivers to S3, not to CloudWatch Logs. A
CloudWatch Logs destination must be added first — it is within the free tier at
lab volume.

---

## OPEN — GitHub environment protection rules are not version-controlled

**Severity:** medium

The promotion gates in [ADR-0012](../adr/0012-environment-promotion-gates.md) —
reviewer counts and the 60-minute production wait — are configured in GitHub's
UI, not in this repository. They can be weakened without a pull request and
without leaving a trace in git history.

**Mitigation:** audit them periodically. GitHub's API can export them for
comparison against the ADR.

---

## OPEN — workflow actions are not pinned to commit SHAs

**Severity:** medium

Workflows reference actions by tag (`actions/checkout@v4`). A tag is mutable: an
attacker who compromises an action repository can move the tag and execute code
in a workflow holding `id-token: write`.

**Fix:** pin to full commit SHAs with the version in a trailing comment, and let
Dependabot propose updates.

---

## Reporting

Security issues in this repository should be raised as a private security
advisory rather than a public issue.
