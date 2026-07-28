# ADR-0010: Private EKS endpoints in production and IRSA for all service accounts

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team, security-team
- **Related:** [ADR-0011](0011-policy-as-code-gates.md), [ADR-0016](0016-no-nat-gateway-in-lab.md)

## Context

An EKS cluster exposes two attack surfaces worth deciding about deliberately:
the Kubernetes API server endpoint, and the way pods obtain AWS credentials.

A public API server endpoint is reachable from the internet and protected by
authentication alone. Pods obtaining credentials from the node instance profile
inherit every permission the node has, which is the union of what every pod on
that node needs.

## Decision

**API server endpoints are private-only in production.** Non-production clusters
may enable the public endpoint restricted by CIDR allow-list.

**Every pod that needs AWS access uses IRSA** — IAM Roles for Service Accounts.
Node instance profiles carry only what the kubelet and CNI require. Pods never
use node credentials.

Secrets are encrypted with a customer-managed KMS key via envelope encryption.

## Alternatives considered

### Public endpoint with an allow-list in production

Depends on a stable set of source addresses, which office and VPN churn make
false. It also leaves the endpoint reachable from anywhere in the allow-listed
ranges, including a compromised laptop.

### kube2iam or kiam

Pre-IRSA solutions that intercept instance metadata calls. They require a
privileged DaemonSet in the traffic path — a component that, if compromised,
can mint credentials for any role. IRSA does the same job with an OIDC provider
and no privileged component.

### Node instance profiles for pod credentials

Simple and coarse: every pod on a node shares one role. Least privilege becomes
impossible, and a compromised sidecar has the same access as the application.

### Pod Identity (the newer EKS mechanism)

A genuine improvement over IRSA — simpler trust, no OIDC provider per cluster.
Worth revisiting; IRSA is chosen here because it is supported across every EKS
version this platform targets and its behaviour is well understood.

## Consequences

### Positive

- The production API server is unreachable from the internet.
- Each pod holds exactly its own permissions; a compromise does not extend to
  its neighbours.
- Credentials are short-lived and rotated automatically by the SDK.
- CloudTrail attributes actions to a service account, not to a node.

### Negative

- A private endpoint means `kubectl` requires a bastion, VPN or SSM session.
  This is real friction during an incident, when friction is most costly.
- CI cannot reach a private cluster without network access, so deployment must
  run in-cluster (GitOps) or through a runner inside the VPC.
- IRSA requires an OIDC provider per cluster and a correctly annotated service
  account. The failure mode — falling back to node credentials — is silent and
  looks like it works.
- A private endpoint requires interface VPC endpoints or NAT for nodes to reach
  the AWS APIs they need.

### Neutral

- Cluster autoscaler, ALB controller, external-secrets and EBS CSI driver all
  get their own IRSA roles.

## Compliance

Checkov enforces private endpoints and encrypted secrets. Kyverno policies in
`kubernetes/kyverno/cluster-policies/` reject pods running as root, privileged
containers, and images from unapproved registries.

## Not deployed in the lab

EKS costs $73/month per cluster before any nodes, and nodes require NAT or
interface endpoints to join. The lab deploys no cluster, so this ADR describes
the target only. The Kyverno and Falco policies are committed and reviewable in
`kubernetes/`.
