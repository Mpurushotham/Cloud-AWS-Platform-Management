# ADR-0016: No NAT gateway in the lab network

- **Status:** Accepted
- **Date:** 2026-07-27
- **Deciders:** platform-team
- **Related:** [ADR-0013](0013-single-account-lab-profile.md), [ADR-0010](0010-private-eks-endpoints-and-irsa.md)

## Context

The production VPC design gives private subnets internet egress through one NAT
gateway per availability zone. Costs, in `us-east-1`:

| Item | Cost |
|------|------|
| NAT gateway | ~$0.045/hour ≈ **$32/month each** |
| NAT data processing | $0.045/GB |
| Elastic IP | $0.005/hour ≈ **$3.60/month each**, attached or not |
| Interface VPC endpoint | ~$0.01/hour/AZ ≈ **$7.30/month each** |

Three AZs of NAT is roughly $107/month before data. The ten interface endpoints
the production design specifies add roughly $73/month more. Against a $0 budget,
neither is available.

Since February 2024 AWS charges for **all** public IPv4 addresses, including
attached Elastic IPs, so there is no free variant of this.

## Decision

The lab VPC has no NAT gateway, no Elastic IP and no interface endpoints.
Private and isolated subnets reach S3 and DynamoDB through **gateway** VPC
endpoints, which are free, and have no other route off the VPC.

Both are implemented behind flags — `enable_nat_gateway` and
`enable_interface_endpoints` — that default to `false`. The production shape
stays in the code, reviewable and one variable away from working.

## What this actually costs in capability

```
Reachable from a private subnet:  S3, DynamoDB
Not reachable:                    STS, Secrets Manager, ECR, CloudWatch,
                                  SSM, KMS, every other AWS API,
                                  and every internet destination
```

Consequences that follow directly:

- **The sample Lambda runs outside the VPC.** Outside, it has normal egress, no
  ENI cold-start penalty and costs nothing. Inside, without NAT or interface
  endpoints, it would time out reaching the very APIs its runtime depends on —
  failures that look like application bugs.
- **EKS and ECS are not deployable.** Managed nodes cannot join a cluster whose
  API endpoint they cannot reach. This is the main reason the lab has no
  Kubernetes layer, and it compounds with [ADR-0010](0010-private-eks-endpoints-and-irsa.md).
- **Nothing in the private tier can install packages** or call a third-party API.

## Alternatives considered

### One shared NAT gateway instead of one per AZ

Halves to a third of the cost (~$32/month) and reintroduces a single-AZ
dependency: an AZ failure removes egress for every AZ. Still $32/month against a
$0 budget. Acceptable for a real non-production environment; not available here.

### A NAT instance on t4g.nano

Roughly $3/month plus the $3.60 IPv4 charge. Genuinely cheaper, and it means
operating a NAT: patching it, monitoring it, handling its failure, and accepting
that its throughput is a single instance's network budget. The operational cost
outweighs the saving for a lab, and it teaches an anti-pattern.

### Interface endpoints for only the essential services

STS, Logs and Secrets Manager alone is ~$22/month across two AZs. The most
defensible middle option, and the first thing to enable given a budget.

### Put everything in public subnets

Would give internet access at no charge and destroys the tiering that is the
main thing the network layer demonstrates. Rejected — the lab exists to show the
right shape.

## Consequences

### Positive

- The network layer costs exactly $0.
- Gateway endpoints are exercised properly, and they are the pattern most often
  missed in real deployments — S3 traffic through a NAT gateway is a common and
  entirely avoidable bill.
- The three-tier topology, route table separation, security group chain and NACL
  behaviour are all genuinely demonstrated.
- The isolated tier's "no route at all" property is real, not simulated.

### Negative

- The private tier is not usable for general workloads, which limits what the
  lab can host to serverless-outside-the-VPC.
- A newcomer may conclude that private subnets do not need egress. They do; this
  is a budget constraint, stated in the layer README and in the network diagram.
- Enabling `attach_to_vpc` on the Lambda without also enabling one of the egress
  flags produces confusing timeouts. Terraform preconditions catch the missing
  subnet arguments but cannot detect the missing egress path.

### Neutral

- Gateway endpoints are attached to the private and isolated route tables, not
  the public one, which does not need them.

## Compliance

`scripts/lab-verify.sh` fails if a NAT gateway, Elastic IP or interface endpoint
appears — each is a recurring charge that should never appear by accident.

## Related defect found

The production `terraform/modules/vpc` cannot apply as written: its isolated
subnets (`cidrsubnet(cidr, 4, i+12)`) fall inside its private subnets
(`cidrsubnet(cidr, 2, i+1)`), so AWS rejects the overlapping CIDR. The lab layer
uses non-overlapping arithmetic, verified for both 2 and 3 AZs. Recorded in
[known issues](../security/known-issues.md).
