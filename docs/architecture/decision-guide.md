# Architecture Decision Guide

Key decisions made in this platform and the reasoning behind each. Use this when evaluating changes to avoid re-litigating settled questions, and as context when proposing exceptions.

---

## Decision 1 — Terraform for Foundation, CDK for Application Layer

**Decision:** Use Terraform for org/network/security primitives; use CDK TypeScript for application-layer stacks.

**Why:**
- Terraform has the most complete AWS provider coverage for org-level resources (Organizations, SCPs, Control Tower, Config aggregator)
- CDK TypeScript provides compile-time safety and L3 constructs for resources that app teams iterate on daily
- The split mirrors the permission boundary: `cap-apply` role manages Terraform state; app teams manage their own CDK stacks
- CDK `addDependency()` enforces stack order without manual `depends_on` chains

**Trade-off accepted:** Two IaC tools to learn. Mitigated by clear ownership (see [iac-selection.md](../when-to-use/iac-selection.md)) and CODEOWNERS preventing cross-boundary edits.

**Exception process:** Any resource that blurs the boundary (e.g., an EKS add-on that needs org-level IAM) must be discussed in `#platform-team` before implementation.

---

## Decision 2 — OIDC Everywhere, Zero Long-Lived Credentials

**Decision:** All CI/CD AWS authentication uses GitHub OIDC. No IAM access keys stored in GitHub Secrets.

**Why:**
- IAM access keys are the most common vector for AWS account compromise
- OIDC tokens are short-lived (15 minutes), bound to a specific repo + branch, and leave a clear audit trail in CloudTrail
- The `cap-apply` role is bound to `refs/heads/main` only — feature branches cannot trigger infrastructure applies
- In the event of a GitHub breach, rotating the OIDC provider is a single Terraform change

**Trade-off accepted:** Local development cannot use the same roles as CI. Developers must use SSO (`aws configure sso`) for local AWS access.

**The four OIDC roles:**
| Role | Trust | What It Can Do |
|------|-------|---------------|
| `cap-plan` | Any branch or PR | Read-only + S3 state read |
| `cap-apply` | `refs/heads/main` only | AdministratorAccess (scoped to non-management) |
| `cap-image-push` | `refs/heads/main` only | ECR push/tag only |
| `cap-prowler` | Any branch | SecurityAudit + ViewOnly |

---

## Decision 3 — S3 + DynamoDB State per Layer

**Decision:** Each Terraform layer (management, logging, security, shared-services, dev, staging, prod) has its own state file with its own DynamoDB lock.

**Why:**
- Blast radius reduction: a failed prod apply cannot corrupt dev state
- Enables parallel applies for independent environments
- Easier access control: prod state is readable only by `cap-plan` and `cap-apply` on main branch
- Follows least-privilege for Terraform itself — management layer apply cannot accidentally modify prod resources

**Trade-off accepted:** More backend configuration to maintain. Mitigated by consistent `backend.tf` template across all environments.

---

## Decision 4 — SCPs as the Outermost Guardrail

**Decision:** SCPs enforce non-negotiable baselines at the OU level. No IAM policy can override an SCP.

**Why:**
- IAM policies are per-account; SCPs are per-OU and cannot be bypassed by anyone in the member account (not even the account root)
- This means security baselines (no root usage, encrypted storage, MFA in prod) cannot be disabled by a compromised account
- Exemption model (ArnNotLike) allows automation roles to perform legitimate operations without weakening the control

**Trade-off accepted:** SCP changes require `@security-team` review and management account apply, which is slower than account-level IAM changes. This is intentional — SCPs should change rarely.

**When SCPs are wrong:** If an SCP is blocking a legitimate new AWS service or pattern, the right response is to add an exemption for the specific automation role, not to remove the SCP. Open a PR to `security/scps/*.json` with a documented justification.

---

## Decision 5 — Private EKS Endpoint in Production

**Decision:** EKS API server is private-endpoint-only in prod. In dev/staging it is public+private.

**Why:**
- Public EKS endpoints expose the Kubernetes API to the internet — even with auth controls, this is an attack surface
- In prod, kubeconfig access requires VPN or SSM bastion — this is an acceptable operational trade-off for the security gain
- Dev/staging uses public+private for developer convenience during early iteration

**Trade-off accepted:** Production cluster debugging requires VPN or SSM jump host. See [kubernetes-workloads.md](../how-to/kubernetes-workloads.md#cluster-access) for access procedure.

---

## Decision 6 — KMS Per Service Per Environment

**Decision:** Each service (S3, RDS, EBS, ElastiCache, CloudWatch, Secrets Manager, etc.) has its own KMS key per environment, named `alias/cap/{env}/kms/{service}`.

**Why:**
- One shared KMS key means a key policy mistake or key compromise exposes all services
- Per-service keys allow granular IAM policies: the RDS role can only decrypt the RDS key
- Key rotation is per-key — rotating one service's key doesn't require touching others
- CloudTrail shows exactly which service decrypted what data

**Trade-off accepted:** 11 KMS keys per environment = 44+ keys total. KMS charges ~$1/key/month — acceptable cost for the isolation.

**Key deletion windows:** 30 days in prod, 7 days in dev/staging. Never set to 0 — KMS deletion is permanent and irreversible.

---

## Decision 7 — Numbered Workflow Convention (00–09)

**Decision:** GitHub Actions workflows are named with two-digit prefixes (00–09) indicating execution order.

**Why:**
- At a glance, anyone can see the pipeline order without reading `needs:` dependencies
- Matches conventions established in `devsecops-gcp` repo for team familiarity
- New workflows can be inserted (01a, or renumbering) without breaking names
- Forces deliberate thinking about where in the pipeline a new check belongs

**Trade-off accepted:** Renumbering is a breaking change to any external references. New workflows added after the initial 10 use descriptive names (`platform-foundation.yml`, `cdk-deploy.yml`).

---

## Decision 8 — Kyverno Enforce Mode (Not Audit) for Critical Policies

**Decision:** The 7 most critical Kyverno policies use `validationFailureAction: Enforce` (blocks pod creation). Only `readonly-rootfs` uses `Audit`.

**Why:**
- Audit mode means a non-compliant pod can still run — it just generates a warning. This creates false security
- Enforce mode means security invariants (no root, no privileged, ECR-only) are guaranteed, not aspirational
- `readonly-rootfs` is in Audit because some legitimate container images (e.g., Prometheus) write temp files to the root filesystem and need a migration path

**Trade-off accepted:** Enforce mode means a misconfigured deployment fails fast and loudly. This is the correct behavior — fix the deployment, not the policy.

**Changing a policy from Enforce to Audit:** Requires `@security-team` approval via CODEOWNERS. Audit-only policies must have a documented timeline for moving back to Enforce.

---

## Decision 9 — No EC2 Key Pairs, SSM Only

**Decision:** No EC2 instances have key pairs. All shell access is via SSM Session Manager.

**Why:**
- SSH keys are a persistent credential that can be stolen and used indefinitely
- SSM access is authenticated via IAM (MFA in prod), logged to CloudTrail, and works through the VPC endpoint without opening port 22
- The `deny-region-restriction` SCP combined with no key pairs means there's no way to get shell access outside the approved flow

**Trade-off accepted:** SSM adds latency (100–200ms) compared to direct SSH. This is acceptable for the security gain. SSM also requires the SSM Agent to be installed and healthy.

---

## Decision 10 — Semantic Release + Conventional Commits

**Decision:** All commit messages must follow conventional commits format. Releases are automated via semantic-release.

**Why:**
- Consistent commit messages make `git log` searchable and generate accurate changelogs
- Semantic versioning is derived from commit types — no manual version bumping
- `security:` commit type signals a security-relevant change in the changelog
- BREAKING CHANGE in a commit body triggers a major version bump automatically

**Trade-off accepted:** Developers must learn the conventional commit format. Enforced by `commitlint` in `00-pre-checks.yml` — non-conforming commits are blocked.
