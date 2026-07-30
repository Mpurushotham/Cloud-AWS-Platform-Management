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

## OPEN — environments pass 68 arguments that the stub modules never declare

**Severity:** blocking for `terraform/environments/**`

Most modules under `terraform/modules/` are unimplemented placeholders. They
declare a handful of variables and create no resources. The environment stacks,
however, call them with a full argument list:

```hcl
module "vpc_endpoints" {
  source      = "../../modules/vpc-endpoints"
  vpc_id      = module.vpc.vpc_id       # not declared by the module
  subnet_ids  = module.vpc.isolated_subnet_ids
  vpc_cidr    = var.vpc_cidr
  environment = "dev"
  project     = "cap"                   # the only variable that exists
}
```

Terraform rejects an argument a module does not declare, so every affected
environment fails at `terraform validate` — before any provider or credential is
involved.

Counted after the HCL parse fixes: **68 undeclared arguments across 11 modules**
(`acm`, `aws-config`, `cloudwatch`, `control-tower`, `ecs`,
`iam-identity-center`, `route53`, `s3`, `security-groups`, `transit-gateway`,
`vpc-endpoints`).

This is why the `Plan — dev/staging/prod` checks cannot pass, and it is a
separate problem from the missing member accounts: even with the accounts, the
configuration would not validate.

**Not fixed here, deliberately.** Two wrong ways to make the symptom disappear:

- Deleting the arguments from the environments — discards the intended design.
- Deleting the unused variables from the modules — was attempted and reverted;
  it removes the documented interface and increases the mismatch, because the
  callers pass *more* than the modules declare, not less.

The correct fix is to implement each module's variable set to match what its
callers pass, module by module, with the resources to use them. That is
substantial work and belongs in its own change.

**Consequence for CI:** TFLint runs with `--minimum-failure-severity=error`, so
the `terraform_unused_declarations` warnings on placeholder modules surface
without blocking. Raise it back to warning severity once the modules are
implemented.

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

---

## FIXED — 110 GitHub Actions were pinned to mutable tags

**Severity:** medium, supply chain

Every workflow referenced actions by tag (`actions/checkout@v4`). A tag is
mutable: whoever controls an action repository can repoint it at new code, which
then executes inside workflows holding `id-token: write` — the permission that
mints AWS credentials.

Three workflows additionally piped a remote install script straight into a
shell:

```yaml
run: |
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh
```

That fetches whatever is on `main` at the moment the job runs and executes it
with the runner's full privileges. Nothing pins it and nothing verifies it.

**Fixed:** all 110 action references are pinned to commit SHAs with the version
in a trailing comment, which Dependabot understands and updates. The three
`curl | sh` installs are replaced with pinned `anchore/sbom-action/download-syft`
and `sigstore/cosign-installer` steps.

Semgrep findings fell from 117 to 3 as a result.

---

## FIXED — Dependabot was never actually enabled

`.github/dependabot.yml` was the unedited GitHub template: `package-ecosystem`
was the empty string and `directory` pointed at `/dependabot/`. No ecosystem was
ever scanned, so no update PR could ever be raised — while the badge and the file
suggested otherwise.

**Fixed:** real configuration for `github-actions`, `npm` (cdk), `terraform` and
`pip`, each with a 7-day `cooldown`. The cooldown matters: a compromised release
is most dangerous in its first days, before anyone has looked at it.

---

## ACCEPTED — three Semgrep warnings remain

| Finding | Why it stays |
|---------|--------------|
| `aws-dynamodb-table-unencrypted` ×2 | AWS-owned key rather than a CMK — the $1/month/key tradeoff in [ADR-0015](../adr/0015-lab-encryption-tradeoffs.md). Data is still encrypted at rest. |
| `allow-privilege-escalation` | The Helm template sets `securityContext` from `.Values.containerSecurityContext`, where `allowPrivilegeEscalation: false` is defined. Semgrep analyses the template statically and cannot resolve `{{ toYaml }}`, so it reports a false positive. |

The SAST job runs with `--severity=ERROR`, so warnings surface in the SARIF
report without blocking a merge. There are currently **zero** ERROR findings.

---

## FIXED — a pinned action was itself on a compromised version

**Severity:** critical

Pinning actions to commit SHAs (above) removed the mutable-tag risk but
introduced a subtler one: **a SHA pins you to a specific version, including a bad
one.** `aquasecurity/trivy-action` was pinned to `v0.33.1`, and
[GHSA-69fq-xp46-6x23](https://github.com/advisories/GHSA-69fq-xp46-6x23) —
*"Trivy ecosystem supply chain was briefly compromised"*, severity **critical** —
affects everything below `0.35.0`.

So the pin was durable and wrong, and would have stayed wrong indefinitely
because a SHA never moves.

**Fixed:** repinned to `v0.36.0`. Note that `0.69.4` is also affected with no
patched release, so "newest" is not automatically safe either.

**The lesson:** SHA pinning and vulnerability scanning are complements, not
alternatives. Pinning makes the supply chain deterministic; only scanning tells
you whether what you pinned is any good. This was caught by Dependabot's alert
on the repository, not by the pinning exercise that created it.

---

## FIXED — conftest policies did not parse

`conftest.rego` used Rego v0 partial-set syntax:

```rego
deny[msg] if { ... }
```

Modern OPA requires `contains` for a partial set rule. Converting all 12 rules to
`deny contains msg if { ... }` then produced a *different* error —
`var cannot be used for rule name` — because the file imported
`future.keywords.if` and `future.keywords.in` but **not**
`future.keywords.contains`.

**Fixed:** added the missing import. `conftest verify` (OPA 1.15.2) passes.

---

## FIXED — three modules could not be validated at all

Surfaced by running `terraform validate` on every module once `versions.tf`
existed to pin a provider. All three had been unvalidatable since they were
written.

**`modules/waf`** declared `resource "aws_wafv2_web_acl_rule"`, which is not a
resource type the AWS provider offers — WAFv2 rules are inline on
`aws_wafv2_web_acl`. The file even carried a comment saying exactly that, while
keeping the block that broke the module.

Worse than the parse error: the web ACL had **no rules at all**. `default_action`
was `allow` and nothing evaluated a request. A WAF in that state bills for
inspecting nothing, which is more dangerous than no WAF because it reads as
protection. It now attaches four AWS managed rule groups — including
`AWSManagedRulesKnownBadInputsRuleSet`, which covers Log4Shell — plus a rate
limit and a logging configuration with `authorization` and `cookie` redacted.

**`modules/s3`** used `lifecycle { prevent_destroy = var.prevent_destroy }`.
Terraform evaluates `lifecycle` before variables, so a variable there is a hard
error. Now a literal `true`: this module backs audit and log buckets, where
accidental deletion is unrecoverable.

**`modules/organizations`** read its SCP documents from
`terraform/modules/scp/policies/`, an empty directory. Repointed to
`security/scps/`, and the templated region policy it expects
(`deny-region.json.tpl`) now exists alongside the static one.

**`modules/rds`** passed `master_username`, which `aws_db_instance` does not
accept — the argument is `username`.

---

## FIXED — a provider-attribute change I introduced

While clearing a deprecation warning I replaced `data.aws_region.<x>.name` with
`.region` across the tree. `.region` exists only in AWS provider 6.x, and the
modules pin `~> 5.0`, so `modules/security-hub` then failed to validate.

The warning had appeared because the modules had **no** `versions.tf` and were
resolving whatever provider was newest. Adding the pins was the real fix;
the attribute rename was chasing a symptom of the missing pin. Reverted.

---

## OPEN — AWS provider 5.x → 6.x upgrade is deferred

**Severity:** technical debt, not a vulnerability

Adding `versions.tf` to all 32 modules made their provider constraint explicit
for the first time, and Dependabot immediately raised **44 pull requests** to
move `hashicorp/aws` from `~> 5.0` to `~> 6.55` — one per module directory.

That is one architectural decision, not 44, and it is a breaking one:

- provider 6 renames `data.aws_region.<name>.name` to `.region`, which
  `modules/security-hub` and `modules/vpc` both use. (This repository has
  already been bitten by the reverse: `.region` was introduced while the
  modules resolved an unpinned provider, then broke once `~> 5.0` was pinned.)
- `CLAUDE.md` states `aws ~> 5.0` as a project convention, so changing it is a
  documented-decision change, not a dependency bump.
- 32 modules and 5 lab layers would all need re-validating together.

**Deferred deliberately.** `.github/dependabot.yml` now groups
`hashicorp/aws` into a single PR and ignores major-version updates for it, so
the noise does not recur. Minor and patch updates still flow normally.

**To do it properly:** write an ADR, change the constraint in one commit across
all modules, fix the `aws_region` attribute references, re-run
`terraform validate` on all 37 directories, and re-run the lab plan to confirm
no resource replacement. Then remove the `ignore` entry.
