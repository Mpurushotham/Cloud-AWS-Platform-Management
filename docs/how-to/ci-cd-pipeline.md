# How to Use the CI/CD Pipeline

## When to Use This Guide

Use this guide when:
- Understanding which workflow runs on which trigger and why
- A pipeline stage is failing and you need to know what it checks
- Adding a new workflow step or modifying pipeline gates
- Debugging a blocked PR or failed apply

---

## Pipeline Overview

Every pull request and merge to `main` runs through numbered workflows (00–09) in sequence. Each workflow is a quality gate — a failing gate blocks the next stage.

```
PR Opened / Push
      │
      ▼
00-pre-checks      ── secrets scan, commit lint, YAML lint
      │ pass
      ▼
01-iac-security    ── checkov, tfsec, tflint, OPA conftest, infracost
      │ pass
      ▼
02-sast            ── CodeQL, semgrep, bandit
      │ pass
      ▼
03-sca             ── trivy filesystem, grype, SBOM generation
      │ pass
      ▼
04-container       ── hadolint, trivy image, cosign signing
      │ pass (on main merge)
      ▼
05-dast            ── OWASP ZAP (non-prod only, scheduled)
      │
      ▼
06-compliance      ── prowler CIS/FSBP/PCI, drift detection
      │
      ▼
07-terraform-plan  ── plan matrix [dev, staging, prod] + OPA gate + PR comment
      │ pass + approved
      ▼
08-terraform-apply ── apply dev (auto) → staging (1 reviewer) → prod (2 + 60min)
      │
      ▼
09-release         ── semantic-release, changelog, SBOM, cosign attest tag
```

---

## Workflow Reference

### `00-pre-checks.yml` — Shift-Left Security Basics

**Triggers:** All PRs, pushes to `main`

**What it checks:**
| Tool | Purpose | Blocks PR? |
|------|---------|-----------|
| gitleaks | Scan for secrets in git history | Yes |
| trufflehog | Deep entropy-based secret detection | Yes |
| commitlint | Enforce conventional commit format | Yes |
| pre-commit | Run all registered pre-commit hooks | Yes |
| yamllint | Lint all YAML files | Yes |
| dependency-review | Flag newly introduced vulnerable deps | Yes |

**Common failures and fixes:**

```bash
# gitleaks false positive — allowlist in .gitleaks.toml:
[allowlist]
  regexes = ['''(?i)example_api_key''']

# Commit message format wrong:
# Bad:  "fix bug in vpc module"
# Good: "fix(networking): correct subnet CIDR overlap in VPC module"

# pre-commit failing locally:
pre-commit run --all-files --show-diff-on-failure
```

---

### `01-iac-security.yml` — Infrastructure as Code Scanning

**Triggers:** PRs and pushes touching `terraform/**`, `cdk/**`, `*.tf`, `*.json`

**What it checks:**
| Tool | Scope | Output |
|------|-------|--------|
| checkov | Terraform + CDK | SARIF → GitHub Security tab |
| tfsec | Terraform | SARIF → GitHub Security tab |
| tflint | Terraform | Inline PR annotations |
| conftest (OPA) | Terraform plan JSON | Pass/fail gate |
| infracost | Terraform | Cost estimate PR comment |

**To run locally:**
```bash
# Checkov
checkov -d terraform/ --config-file .checkov.yml --output sarif

# tfsec
tfsec terraform/ --exclude-downloaded-modules

# OPA — requires a plan file
cd terraform/environments/dev
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test plan.json --policy ../../conftest.rego

# infracost (requires INFRACOST_API_KEY)
infracost breakdown --path terraform/environments/dev
```

**To skip a checkov rule (documented false positive):**
```python
# In your Terraform file, add a comment:
#checkov:skip=CKV_AWS_123:Justification - this bucket is intentionally public for static website
```

---

### `02-sast.yml` — Static Application Security Testing

**Triggers:** PRs and pushes touching `cdk/**`, `security/**`, `scripts/**`, `*.py`, `*.ts`

**What it checks:**
| Tool | Language | Ruleset |
|------|---------|---------|
| CodeQL | TypeScript, Python | GitHub default + security-extended |
| semgrep | TypeScript, Python | p/aws-lambda, p/python, p/owasp-top-ten, p/secrets |
| bandit | Python only | All rules, SARIF output |

**To run locally:**
```bash
# semgrep
semgrep --config p/python --config p/owasp-top-ten security/

# bandit
bandit -r security/ -f sarif -o bandit-results.sarif
```

---

### `03-sca.yml` — Software Composition Analysis

**Triggers:** PRs touching `cdk/package*.json`, `requirements*.txt`, `Dockerfile`

**What it checks:**
- `trivy filesystem` — known CVEs in all dependencies
- `grype` — second-opinion vulnerability scanner
- `syft` — generates SPDX + CycloneDX SBOMs, uploaded as workflow artifacts

**Fix a vulnerable dependency:**
```bash
# Check which package is vulnerable
trivy fs . --format table | grep HIGH

# Update in package.json / requirements.txt
npm update vulnerable-package

# Or pin to a safe version
pip install "requests>=2.31.0"
```

---

### `04-container-security.yml` — Container Image Security

**Triggers:** Pushes to `main` that touch `Dockerfile` or `ecs/`

**What it checks:**
1. `hadolint` — Dockerfile best practices (no `latest` tags, no `apt-get` without pinned versions)
2. `trivy image` — scan built image for OS + library CVEs
3. `cosign sign` — keyless signing with GitHub OIDC (Sigstore Fulcio)
4. Attestation — attaches SBOM to image in ECR

**To verify an image signature:**
```bash
cosign verify \
  --certificate-identity "https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/.github/workflows/04-container-security.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/cap-dev-api:SHA
```

---

### `05-dast.yml` — Dynamic Application Security Testing

**Triggers:** Schedule (nightly, non-prod only) + manual dispatch

**What it checks:**
- OWASP ZAP baseline scan against dev API Gateway endpoint
- ZAP full API scan using OpenAPI spec

**Not triggered on PRs** (requires a running environment). Results posted as PR comment when triggered manually.

---

### `06-compliance.yml` — Compliance Scanning + Drift Detection

**Triggers:** Schedule (daily 6 AM UTC) + manual dispatch

**What it checks:**
- Prowler: CIS AWS Foundations 1.4, AWS FSBP, PCI-DSS 3.2.1
- Drift detection: `terraform plan --detailed-exitcode` for dev/staging/prod
- Results uploaded as CSV + JSON artifacts

**To trigger manually:**
```bash
gh workflow run 06-compliance.yml -f environment=prod
```

---

### `07-terraform-plan.yml` — Terraform Plan + OPA Gate

**Triggers:** All PRs touching `terraform/**`

**What it does:**
1. Assumes `cap-plan` OIDC role (read-only)
2. Runs `terraform init → fmt → validate → plan` for each environment in matrix
3. Converts plan to JSON and runs `conftest test` (OPA policies)
4. Posts a formatted plan summary as PR comment
5. Blocks merge if OPA gate fails

**Reading the PR comment:**
```
## Terraform Plan — dev ✅
| Resource | Action |
|----------|--------|
| aws_vpc.main | + create |
| aws_subnet.private[0] | + create |

OPA/conftest: ✅ 0 violations

Estimated cost change: +$47.20/month
```

**If OPA gate fails:**
```
OPA/conftest: ❌ 2 violations
- DenyPublicS3: S3 bucket cap-dev-logs has public access enabled
- RequireKMSRotation: KMS key alias/cap/dev/kms/rds has rotation disabled
```

Fix the Terraform code that caused the violation, push again.

---

### `08-terraform-apply.yml` — Terraform Apply with Environment Gates

**Triggers:** Merge to `main` (touches `terraform/**`)

**Gate model:**
| Environment | Reviewer Requirement | Wait Timer |
|-------------|---------------------|-----------|
| dev | None (auto-approve) | 0 min |
| staging | 1 reviewer | 0 min |
| prod | 2 reviewers | 60 min |

**To approve an apply:**
1. Go to `Actions → 08-terraform-apply → [run] → Review deployments`
2. Select the environment (staging or prod)
3. Click Approve and deploy

**To roll back a bad apply:**
```bash
# Revert the commit that triggered the bad apply
git revert HEAD --no-edit
git push origin main
# 08-terraform-apply.yml triggers automatically and applies the revert
```

---

### `09-release.yml` — Semantic Release + SBOM + Attestation

**Triggers:** Pushes to `main` with conventional commits

**What it does:**
1. `semantic-release` reads conventional commits → bumps version → creates GitHub release + tag
2. Generates SBOM for the release commit
3. `cosign attest` attaches SBOM to the release tag

**Commit types and version bumps:**
| Prefix | Version Bump | Example |
|--------|-------------|---------|
| `feat:` | Minor (0.X.0) | `feat(eks): add spot instance support` |
| `fix:` | Patch (0.0.X) | `fix(vpc): correct NAT gateway EIP association` |
| `security:` | Patch | `security(scp): restrict region to us-east-1 only` |
| `feat!:` or `BREAKING CHANGE:` | Major (X.0.0) | `feat!: migrate state backend to new bucket` |

---

## Adding a New Pipeline Step

1. Create `.github/workflows/XX-new-step.yml` (use next available number)
2. Follow the OIDC pattern — never hardcode credentials:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: ${{ secrets.CAP_PLAN_ROLE_ARN }}
       aws-region: us-east-1
   ```
3. Upload security findings as SARIF to GitHub Security tab:
   ```yaml
   - uses: github/codeql-action/upload-sarif@v3
     with:
       sarif_file: results.sarif
   ```
4. Add a `needs:` dependency to the appropriate downstream workflow
