# When to Use Terraform vs CDK vs Manual

## Quick Decision Table

| Scenario | Use |
|----------|-----|
| Organization, OUs, SCPs, member accounts | Terraform |
| VPC, subnets, Transit Gateway, NAT GWs | Terraform |
| Security services (GuardDuty, Security Hub, Config, CloudTrail) | Terraform |
| IAM Identity Center, permission sets | Terraform |
| KMS keys, IAM roles (platform-level) | Terraform |
| ECR repositories, Route53 hosted zones | Terraform |
| EKS cluster, ECS cluster, RDS instances | Terraform |
| Application CDK stack (Lambda, API GW, S3 app buckets) | CDK |
| Service-level KMS keys, per-service IAM roles | CDK |
| CloudWatch dashboards, composite alarms per service | CDK |
| One-time emergency change (account compromise, etc.) | Manual (document afterward) |
| Anything touched by application teams daily | CDK |
| Anything shared across multiple teams/environments | Terraform |

---

## Terraform — When and Why

**Use Terraform for:**
- Infrastructure that changes infrequently and is shared across teams
- AWS Organizations, account structure, SCPs — things that require careful review
- Network primitives (VPC, subnets, routing) — wrong values cause outages
- Security services — requires consistent, auditable configuration
- Any resource where you need `depends_on` across AWS accounts

**Why Terraform here:**
- Mature AWS provider ecosystem with the most complete resource coverage
- `terraform plan` output is easy for security teams to review
- State stored in S3 gives a reliable source of truth
- `prevent_destroy` lifecycle rule protects critical resources
- Works well with OPA/conftest for policy-as-code gates

**Terraform file structure (per module):**
```
modules/my-module/
├── main.tf          # module-level locals, data sources
├── specific.tf      # purpose-named files (networking.tf, security.tf, etc.)
├── variables.tf     # input variables with descriptions and types
├── outputs.tf       # exported values
├── versions.tf      # required_providers, required_version
└── README.md        # usage example, inputs/outputs table
```

---

## CDK (TypeScript) — When and Why

**Use CDK for:**
- Resources that application teams create and iterate on frequently
- Multi-stack applications where order of deployment matters
- Type-safe L3 constructs that encapsulate best practices
- Resources that need programmatic logic (loops, conditionals, lookups)
- Stack outputs consumed by other stacks in the same CDK app

**Why CDK here:**
- TypeScript type safety catches mistakes at compile time
- L3 constructs (e.g., `SecureVpcConstruct`) encode security defaults by construction
- `addDependency()` enforces deployment order without manual `depends_on`
- `cdk diff` is fast and developer-friendly for frequent iteration
- Native AWS constructs track CloudFormation for free (rollback, change sets)

**CDK stack dependency order (always respect this):**
```
NetworkStack → SecurityStack → PlatformStack → DataStack → ApiStack → ObservabilityStack
```

**Reading context in CDK:**
```typescript
// cdk/bin/app.ts — read environment from context
const environment = app.node.tryGetContext("environment") ?? "dev";
const config = app.node.tryGetContext(environment);
```

---

## The Split — What Lives Where

```
Terraform                              CDK
───────────────────────────────────── ─────────────────────────────────────
AWS Organization (accounts, OUs, SCPs) EKS Kubernetes add-ons (via Helm)
VPC, subnets, routing tables           API Gateway + Lambda + CloudFront
Transit Gateway + RAM shares           Service-specific S3 buckets
Security Hub, GuardDuty, Config        Service-specific KMS keys
IAM Identity Center + permission sets  CloudWatch dashboards per service
KMS keys (platform keys)               Composite alarms
ECR repositories (platform-managed)    WAF rules (application-level)
RDS, ElastiCache (shared infra)        X-Ray groups
EKS cluster + node groups              Application load balancers
```

**The rule of thumb:** If a resource is provisioned once and shared by many services, it belongs in Terraform. If a resource is created per-service or per-team, it belongs in CDK.

---

## Manual Changes — When and How

Avoid manual changes. The only acceptable cases:

| Scenario | Why Manual | What to Do Afterward |
|----------|-----------|---------------------|
| Bootstrap (before OIDC exists) | Chicken-and-egg | Import resources into Terraform state |
| Incident response (role revocation) | Time-critical | Document in incident ticket, add to IaC |
| AWS console exploratory work | Prototyping | Delete manually, implement in IaC |
| Account creation via vending script | Automated script | Record account ID in Terraform variables |

**After any manual change:** run `terraform plan` to detect drift and immediately create a PR that codifies the change.

```bash
# Detect drift
./scripts/drift-detection.sh

# Import an existing resource that was created manually
terraform import aws_vpc.main vpc-xxxxxx
```

---

## Anti-Patterns to Avoid

| Anti-Pattern | Why It's Problematic | Better Approach |
|-------------|---------------------|----------------|
| CDK for org-level resources | No state locking, harder to review | Terraform |
| Terraform for per-service app config | Slow feedback loop, not type-safe | CDK |
| Mixing CDK + Terraform in same resource | Drift and ownership conflicts | Pick one per resource |
| `local-exec` provisioners in Terraform | Not idempotent, hard to test | Use a proper resource or data source |
| CloudFormation directly (outside CDK) | No type safety, verbose syntax | Use CDK which compiles to CF |
| Terraform modules with >500 lines in one file | Hard to review, hard to test | Split into purpose-named files |
