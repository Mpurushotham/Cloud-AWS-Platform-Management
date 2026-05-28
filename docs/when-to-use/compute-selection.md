# When to Use EKS vs ECS vs Lambda vs EC2

## Quick Decision Flowchart

```
Is the workload stateless?
    ├── No ──► EKS (with PersistentVolumes) or RDS/ElastiCache (for data)
    └── Yes ─► Does it run longer than 15 minutes?
                   ├── No ──► Is it event-driven?
                   │             ├── Yes ──► Lambda
                   │             └── No  ──► ECS Fargate
                   └── Yes ─► Does it need sidecar containers or service mesh?
                                  ├── Yes ──► EKS
                                  └── No  ──► ECS Fargate
```

---

## EKS — When to Use It

**Use EKS when:**
- Service requires sidecar injection (Envoy, Istio, Linkerd, Dapr)
- Complex pod scheduling (GPU nodes, topology spread, node affinity)
- Fine-grained autoscaling beyond CPU/memory (KEDA, custom metrics HPA)
- Service mesh for mTLS between services
- Team already has Kubernetes expertise
- Workload needs StatefulSets (Kafka, ZooKeeper, stateful databases)
- Batch jobs with complex DAGs (Argo Workflows, Apache Airflow on K8s)

**Do not use EKS when:**
- You just want to run a container — ECS is much simpler
- Team has no Kubernetes experience — operational overhead is high
- Workload runs < 1 hour and is event-triggered — Lambda is cheaper
- Cost is a major constraint — EKS cluster baseline ~$73/month + node costs

**Platform configuration:** `cap-{env}-eks` cluster — private endpoint in prod, public+private in dev/staging.

```bash
# Access
aws eks update-kubeconfig --name cap-dev-eks --region us-east-1

# Node groups
kubectl get nodes -L eks.amazonaws.com/nodegroup
# system-nodes:  t3.medium × 2 (on-demand, taints system workloads)
# general-nodes: t3.large × 2-10 (on-demand, HPA target)
# spot-nodes:    mixed × 0-20 (spot, non-critical batch)
```

---

## ECS Fargate — When to Use It

**Use ECS Fargate when:**
- Running a simple HTTP API, background worker, or queue consumer
- Team is not Kubernetes-native
- You want zero node management (Fargate = serverless containers)
- Workload runs continuously but doesn't need sidecars
- Need to move fast — ECS deploys are simpler to configure and debug

**ECS is the default.** Most services on this platform should use ECS unless there is a specific reason to use EKS.

**Platform clusters:**
- `cap-dev-ecs` — dev ECS cluster (Fargate + Fargate Spot)
- `cap-staging-ecs` — staging cluster
- `cap-prod-ecs` — prod cluster (Fargate only, no Spot)

**Task definition minimums (enforced by SCP + Checkov):**
```json
{
  "cpu": "256",
  "memory": "512",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "containerDefinitions": [{
    "readonlyRootFilesystem": true,
    "user": "1000:1000",
    "linuxParameters": {
      "initProcessEnabled": true,
      "capabilities": {"drop": ["ALL"]}
    }
  }]
}
```

---

## Lambda — When to Use It

**Use Lambda when:**
- Execution time < 15 minutes
- Event-driven: S3 put, SQS message, API GW request, EventBridge rule
- Infrequent or spiky traffic (Lambda scales to zero — no idle cost)
- Config rules remediation, GuardDuty response automation
- Simple data transformations in a pipeline

**Do not use Lambda when:**
- Workload runs > 15 minutes
- Requires in-memory state between invocations
- Needs a persistent TCP connection (e.g., database connection pool)
- Cold start latency is unacceptable for your p99 (Lambda adds 100ms–2s on cold start)

**Existing Lambda use in this platform:**
- `security/remediation-lambdas/auto-remediation/handler.py` — Config remediation
- `security/remediation-lambdas/guardduty-response/handler.py` — GuardDuty response
- `security/config-rules/custom-rules/require-imdsv2.py` — Custom Config rule evaluator

**Lambda requirements (enforced by OPA + Checkov):**
- KMS encryption for environment variables
- Dead-letter queue configured (SQS)
- Reserved concurrency set (prevent runaway invocations)
- X-Ray active tracing enabled
- VPC attachment when accessing private resources

---

## EC2 — When to Use It

EC2 is **not the default** for any new workload on this platform. The only acceptable uses:

| Use Case | Instance Type | Notes |
|----------|-------------|-------|
| EKS node groups (managed by EKS) | t3.medium / t3.large | Never directly manage — use EKS node groups |
| SSM bastion for private cluster access | t3.micro | Only one per environment, no key pairs |
| Legacy workload migration (temporary) | As needed | Must have migration plan to ECS/EKS |
| GPU workloads | g4dn / p3 | Must use EKS GPU node group |

**All EC2 instances must have:**
- IMDSv2 (`http_tokens = required`) — enforced by SCP + OPA
- No key pairs — use SSM Session Manager
- Encrypted EBS volumes — enforced by SCP
- EC2 Instance Connect or SSM for access
- SSM Agent installed

```bash
# Access via SSM (never SSH)
aws ssm start-session --target i-INSTANCE_ID --region us-east-1
```

---

## Cost Comparison (approximate, us-east-1)

| Option | 1 vCPU / 2GB RAM | Notes |
|--------|-----------------|-------|
| Lambda | $0–$10/month | At 100ms avg duration, 1M req/month |
| ECS Fargate | ~$35/month | Continuous, 0.25 vCPU / 0.5 GB |
| ECS Fargate Spot | ~$15/month | 70% cheaper, can be interrupted |
| EKS + t3.medium | ~$110/month | Includes $73 cluster fee |
| EC2 t3.small on-demand | ~$15/month | Plus management overhead |

Use `infracost` in the CI pipeline to see actual estimated cost for your configuration:
```bash
infracost breakdown --path terraform/environments/dev
```

---

## Summary

| Criterion | Lambda | ECS Fargate | EKS | EC2 |
|-----------|--------|------------|-----|-----|
| Max runtime | 15 min | Unlimited | Unlimited | Unlimited |
| Scales to zero | Yes | No | No | No |
| Node management | None | None | Managed by EKS | Full |
| Sidecars | No | Limited | Yes | Yes |
| Cold start | Yes | No | No | No |
| Default for new services | Event-driven | Yes | Complex workloads | No |
| Cost model | Per invocation | Per hour | Per hour + cluster | Per hour |
