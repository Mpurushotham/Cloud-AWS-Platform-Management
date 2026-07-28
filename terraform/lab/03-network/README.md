# Lab Layer 03 — Network

> **Navigation:** [Lab README](../README.md) | [Network Diagram](../../../docs/architecture/diagrams/02-network-topology.md) | [ADR-0016 No NAT in Lab](../../../docs/adr/0016-no-nat-gateway-in-lab.md)

A three-tier VPC that matches the production topology in shape while costing
nothing to run.

## What it creates

| Resource | Count | Cost |
|----------|-------|------|
| VPC `10.10.0.0/16` | 1 | $0 |
| Internet gateway | 1 | $0 |
| Subnets (public / private / isolated) | 6 | $0 |
| Route tables | 4 | $0 |
| Gateway VPC endpoints (S3, DynamoDB) | 2 | **$0 — gateway endpoints are free** |
| Security groups + rules | 4 SGs, 8 rules | $0 |
| Network ACL (isolated tier) | 1 | $0 |
| VPC flow logs → CloudWatch | 1 | ~$0 within 5 GB free tier |
| NAT gateways | **0** | would be ~$32/mo each |
| Interface endpoints | **0** | would be ~$7.30/mo each |

## Subnet layout (`az_count = 2`)

| Tier | AZ a | AZ b | Route to internet |
|------|------|------|-------------------|
| public | `10.10.0.0/24` | `10.10.1.0/24` | via internet gateway |
| private | `10.10.4.0/22` | `10.10.8.0/22` | none in lab (NAT disabled) |
| isolated | `10.10.100.0/24` | `10.10.101.0/24` | none, by design |

The offsets are chosen so the tiers cannot overlap at either `az_count` value.
This is worth stating explicitly because `terraform/modules/vpc` gets it wrong:
its isolated `/20`s fall inside its private `/18`s, so that module cannot apply
as written. See [known issues](../../../docs/security/known-issues.md).

## What "no NAT gateway" actually costs you

Private-subnet workloads can reach **S3 and DynamoDB** through the free gateway
endpoints, and nothing else. They cannot reach:

- other AWS service APIs (STS, Secrets Manager, ECR, CloudWatch) — those need
  interface endpoints or NAT
- any internet destination — package installs, third-party APIs, webhooks

Consequences for the lab:

- the sample Lambda in layer 04 runs **outside** the VPC, which is free and has
  full internet egress
- EKS and ECS are not deployed; managed nodes cannot join a cluster without
  reaching the EKS API endpoint

To make the private tier fully functional, set `enable_nat_gateway = true`
(~$32/month per AZ) or `enable_interface_endpoints = true` (~$7.30/month per
endpoint per AZ). Both are wired and tested — they are switched off, not absent.

## Apply

```bash
cd terraform/lab/03-network
terraform init
terraform plan  -out=tfplan
terraform apply tfplan
```

## Verification

```bash
VPC="$(terraform output -raw vpc_id)"

# Confirm no NAT gateway and no Elastic IP exist
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" --query 'NatGateways[?State!=`deleted`]'
aws ec2 describe-addresses --query 'Addresses'

# Confirm both gateway endpoints are attached
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" \
  --query 'VpcEndpoints[].{Service:ServiceName,Type:VpcEndpointType,State:State}' --output table

# Confirm the default security group denies everything
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].{In:IpPermissions,Out:IpPermissionsEgress}'

# Confirm flow logs are active
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC" \
  --query 'FlowLogs[].{Status:FlowLogStatus,Dest:LogDestinationType}'
```
