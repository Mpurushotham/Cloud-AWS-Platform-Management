# How to Add a New Service to the Platform

## When to Use This Guide

Use this guide when:
- A team wants to deploy a **new microservice, API, or background worker** onto the platform
- Onboarding a service from another cloud or on-premise into the CAP environment
- Creating a net-new internal product from scratch on the platform

---

## Step 1 — Choose the Right Golden Path

| Service Type | Template | Runtime | Infra |
|-------------|---------|---------|-------|
| HTTP REST API | `idp/templates/rest-api-service` | ECS Fargate | API GW + ALB + RDS |
| Background worker / queue consumer | `idp/templates/ecs-microservice` | ECS Fargate | SQS + ECS |
| Kubernetes workload (complex, stateful) | `idp/templates/eks-workload` | EKS | EKS + PVC |
| Event-driven function | `idp/templates/lambda-function` | Lambda | Event Bridge + SQS |
| Data pipeline | `idp/templates/data-pipeline` | ECS/Glue | S3 + Glue + RDS |

**Decision rule:** Default to ECS Fargate (simpler ops). Use EKS only for workloads that need sidecar injection, service mesh, or fine-grained pod autoscaling. Use Lambda for sub-60s, stateless, event-triggered work.

---

## Step 2 — Generate the Service Scaffold

```bash
pip install cookiecutter
cookiecutter idp/templates/rest-api-service/

# Prompts:
# service_name: payment-api
# team_name: payments-team
# environment: dev
# aws_account_id: 666666666666
# ecr_registry: 666666666666.dkr.ecr.us-east-1.amazonaws.com
```

This generates a new directory `payment-api/` with:
```
payment-api/
├── Dockerfile              # non-root, minimal base, multi-stage
├── .github/workflows/
│   └── deploy.yml          # build → scan → push → deploy
├── cdk/
│   └── lib/payment-api-stack.ts
├── src/                    # application source
├── tests/
└── .pre-commit-config.yaml
```

---

## Step 3 — Create the ECR Repository

```bash
# Open a PR adding your service to terraform/modules/ecr/
# Add an entry in the ecr_repositories variable in shared-services/main.tf:

module "ecr" {
  source = "../../modules/ecr"
  repositories = [
    "cap-payment-api",  # add this line
    ...
  ]
}
```

After merge, the pipeline creates the ECR repo automatically. Or pre-create it:
```bash
aws ecr create-repository \
  --repository-name cap-dev-payment-api \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=KMS \
  --region us-east-1
```

---

## Step 4 — Add OIDC Trust for the Service Repository

Your service's GitHub Actions need permission to push images and deploy:

```bash
# In terraform/bootstrap/oidc.tf, add your repo to cap-image-push trusted repos:
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = [
    "repo:Mpurushotham/Cloud-AWS-Platform-Management:*",
    "repo:your-org/payment-api:ref:refs/heads/main",  # add this
  ]
}
```

Open a PR to the platform repo. The `@platform-team` owns this file and will review.

---

## Step 5 — Build and Push Your Container Image

```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS \
  --password-stdin 666666666666.dkr.ecr.us-east-1.amazonaws.com

# Build (multi-stage, non-root)
docker build -t cap-dev-payment-api:latest .

# Scan before push (must pass)
trivy image --exit-code 1 --severity CRITICAL cap-dev-payment-api:latest

# Tag and push
docker tag cap-dev-payment-api:latest \
  666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-payment-api:latest
docker push 666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-payment-api:latest

# Sign with cosign (keyless)
cosign sign --yes \
  666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-payment-api:latest
```

---

## Step 6 — Deploy the CDK Stack

```bash
cd payment-api/cdk
npm ci && npm test    # must pass

# Deploy to dev
npx cdk deploy PaymentApiStack --context environment=dev

# Verify the stack
aws cloudformation describe-stacks \
  --stack-name PaymentApiStack-dev \
  --query 'Stacks[0].StackStatus'
```

---

## Step 7 — For EKS Workloads — Apply Kubernetes Manifests

If using the `eks-workload` template:

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name cap-dev-eks \
  --region us-east-1

# Apply namespace first (restricts to platform PSS)
kubectl apply -f kubernetes/namespaces/applications.yaml

# Deploy via Helm chart
helm upgrade --install payment-api \
  kubernetes/helm-charts/microservice/ \
  --namespace applications \
  --set image.repository=666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-payment-api \
  --set image.tag=latest \
  --set replicaCount=2
```

Kyverno will enforce:
- Non-root container (UID ≥ 1000)
- No latest tag in staging/prod
- ECR-only registry
- CPU/memory limits set
- Read-only root filesystem

Fix any Kyverno policy violations before the pods will start.

---

## Step 8 — Configure Observability

Your service gets observability automatically through the platform, but add service-specific alarms:

```bash
# Add to monitoring/cloudwatch/alarms/security-alarms.json:
{
  "AlarmName": "cap-dev-payment-api-5xx-rate",
  "MetricName": "5XXError",
  "Namespace": "AWS/ApplicationELB",
  "Threshold": 10,
  "EvaluationPeriods": 2,
  "Period": 60,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": ["arn:aws:sns:us-east-1:ACCOUNT:cap-dev-alerts"]
}
```

---

## Promotion Path: Dev → Staging → Prod

| Stage | Trigger | Gate |
|-------|---------|------|
| Dev | Auto on merge to `main` | Kyverno + trivy must pass |
| Staging | Workflow: `08-terraform-apply.yml` | 1 reviewer approval |
| Prod | Workflow: `08-terraform-apply.yml` | 2 reviewer approvals + 60-min wait |

```bash
# Promote image to prod (retag, don't rebuild)
docker pull 666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-payment-api:SHA
docker tag ... 999999999999.dkr.ecr.us-east-1.amazonaws.com/cap-prod-payment-api:SHA
docker push ...
cosign sign --yes ...
```

---

## Checklist Before Going to Production

- [ ] Container runs as non-root (UID 1000)
- [ ] No `latest` tag — use immutable SHA tags
- [ ] `readOnlyRootFilesystem: true` in pod spec
- [ ] CPU and memory requests + limits defined
- [ ] Liveness and readiness probes configured
- [ ] PodDisruptionBudget set (minAvailable ≥ 1)
- [ ] Secrets in AWS Secrets Manager (not environment variables)
- [ ] IRSA role with least-privilege policy (no `*` actions)
- [ ] CloudWatch alarms for error rate, latency p99
- [ ] Container image signed with cosign
- [ ] Trivy scan shows zero CRITICAL vulnerabilities
