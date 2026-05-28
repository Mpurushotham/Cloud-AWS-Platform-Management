# How to Deploy Kubernetes Workloads

## When to Use This Guide

Use this guide when:
- Deploying a containerized workload to EKS using the platform Helm chart
- Troubleshooting a pod that won't start due to Kyverno policy violations
- Understanding network policies and why a pod can't reach another service
- Setting up IRSA (IAM Roles for Service Accounts) for AWS access from pods

---

## Cluster Access

```bash
# Get credentials for dev cluster
aws eks update-kubeconfig \
  --name cap-dev-eks \
  --region us-east-1 \
  --profile cap-dev

# Verify connection
kubectl cluster-info
kubectl get nodes -o wide
```

Cluster is **private endpoint only in prod** — you must be on the VPN or use an SSM-proxied bastion to reach the API server in production.

```bash
# Access prod cluster via SSM bastion
aws ssm start-session --target i-BASTION_ID --region us-east-1
# Inside bastion:
aws eks update-kubeconfig --name cap-prod-eks
```

---

## Namespace Structure

| Namespace | PSS Level | Who Uses It |
|-----------|----------|------------|
| `platform` | Restricted | Platform infrastructure (ingress, cert-manager) |
| `applications` | Restricted | Application team workloads |
| `security` | Privileged | Falco (needs host access), Kyverno |
| `monitoring` | Restricted | Prometheus, Grafana |
| `kube-system` | Privileged | Core Kubernetes components |

Always deploy application workloads to `applications` namespace.

---

## Deploying with the Platform Helm Chart

```bash
# Basic deploy
helm upgrade --install my-service \
  kubernetes/helm-charts/microservice/ \
  --namespace applications \
  --create-namespace \
  --values my-service-values.yaml

# Dry run first to see what will be created
helm upgrade --install my-service \
  kubernetes/helm-charts/microservice/ \
  --namespace applications \
  --dry-run \
  --values my-service-values.yaml
```

### Minimum `values.yaml`

```yaml
image:
  repository: 666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-my-service
  tag: "sha-abc1234"    # never use 'latest' in staging/prod

replicaCount: 2

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

serviceAccount:
  name: my-service-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::666666666666:role/cap-dev-my-service-irsa

livenessProbe:
  httpGet:
    path: /health
    port: 8080

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
```

---

## Kyverno Policies — What Gets Enforced

All workloads in `applications` namespace are subject to these Kyverno cluster policies:

| Policy | Level | What It Checks |
|--------|-------|---------------|
| `no-privileged` | Enforce | `securityContext.privileged` must be false |
| `no-root` | Enforce | `runAsNonRoot: true` + `runAsUser >= 1000` |
| `deny-latest-tag` | Enforce | Image tag cannot be `latest` in staging/prod |
| `require-labels` | Enforce | Must have `app`, `version`, `team` labels |
| `require-resources` | Enforce | CPU + memory requests and limits must be set |
| `allowed-registries` | Enforce | Only ECR registries allowed (no Docker Hub) |
| `no-privilege-escalation` | Enforce | `allowPrivilegeEscalation: false` |
| `readonly-rootfs` | Audit | `readOnlyRootFilesystem: true` (logs warning, does not block) |

### Fix Common Kyverno Rejections

**Pod rejected: running as root**
```yaml
# Add to container spec:
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
```

**Pod rejected: no resource limits**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

**Pod rejected: image from non-ECR registry**
```yaml
# Change image to ECR:
image: 666666666666.dkr.ecr.us-east-1.amazonaws.com/cap-dev-my-service:sha-abc1234
# Not: nginx:latest or docker.io/library/nginx
```

**Pod rejected: missing labels**
```yaml
metadata:
  labels:
    app: my-service
    version: "1.2.3"
    team: payments-team
```

---

## Setting Up IRSA (AWS Access from Pods)

IRSA lets pods assume an IAM role without static credentials.

### Step 1 — Create the IAM role (Terraform)

In your service's CDK or Terraform, create an IRSA role:

```hcl
module "irsa" {
  source      = "../../modules/iam"
  environment = var.environment

  irsa_roles = {
    "my-service" = {
      namespace       = "applications"
      service_account = "my-service-sa"
      policy_arns     = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
      # Use least-privilege custom policy in production
    }
  }
}
```

### Step 2 — Annotate the Kubernetes Service Account

```yaml
# In your Helm values.yaml:
serviceAccount:
  create: true
  name: my-service-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::666666666666:role/cap-dev-my-service-irsa
```

### Step 3 — Verify IRSA is Working

```bash
# Exec into the pod and test AWS access
kubectl exec -it my-service-PODID -n applications -- /bin/sh

# Inside pod:
aws sts get-caller-identity
# Should return the IRSA role ARN, not the EC2 instance profile
```

---

## Network Policies

By default, all inter-pod traffic is **denied** by the `default-deny-all` network policy.

Pods can only communicate if there is an explicit allow rule.

### What is allowed by default

- DNS (UDP/TCP port 53) from all pods to `kube-dns`
- Prometheus scraping from `monitoring` namespace on any port
- Inter-pod traffic within the same namespace

### Add a custom allow policy

```yaml
# Allow my-service to reach the postgres pod in the same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-my-service-to-postgres
  namespace: applications
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: my-service
      ports:
        - protocol: TCP
          port: 5432
```

### Debugging connectivity

```bash
# Test connectivity between pods
kubectl run netcheck --image=busybox --rm -it -- sh
# Inside:
nc -zv postgres-service.applications.svc.cluster.local 5432

# Check which network policies apply to a pod
kubectl describe pod my-service-PODID -n applications | grep -A5 "Network Policy"
```

---

## Falco Runtime Alerts

Falco monitors all pods for suspicious behavior. Common alerts that indicate a real issue:

| Alert | Severity | Meaning |
|-------|---------|---------|
| `aws_imds_access_from_container` | Warning | Pod accessing EC2 metadata — might be stealing credentials |
| `aws_credentials_file_read` | Critical | Credential file read inside container |
| `crypto_mining_detected` | Critical | Known mining binary or port (4444, 3333, 14444) |
| `shell_in_container` | Notice | Shell spawned — expected in debug, not in prod |
| `privilege_escalation_via_setuid` | Critical | setuid bit manipulation |

**If you see a `shell_in_container` alert from your own debugging:**
```bash
# Acknowledge in PagerDuty + add a suppression entry if it's a known debug session
# suppression file: security/guardduty/findings-suppression.json
```

---

## Horizontal Pod Autoscaler

The platform Helm chart includes HPA configuration:

```yaml
# In values.yaml:
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

```bash
# Check HPA status
kubectl get hpa -n applications
kubectl describe hpa my-service -n applications
```

---

## PodDisruptionBudget

Always set a PDB to prevent all replicas being evicted during node upgrades:

```yaml
# In values.yaml:
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

```bash
# View PDBs
kubectl get pdb -n applications
```
