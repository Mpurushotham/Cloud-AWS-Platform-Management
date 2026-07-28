# Lab layer 03 — network.
#
# Resource files:
#   networking.tf — VPC, internet gateway, default resource lockdown
#   subnets.tf    — public / private / isolated tiers
#   routing.tf    — route tables and gateway endpoints
#   rules.tf      — security groups and NACLs
#   flow-logs.tf  — VPC flow logs to CloudWatch
#
# This layer does not reuse terraform/modules/vpc. That module always creates
# one NAT gateway per AZ, which the lab budget cannot absorb, and its subnet
# arithmetic produces overlapping ranges (see docs/security/known-issues.md).

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "cap-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Subnet arithmetic, chosen so the three tiers cannot overlap for any
  # az_count in [2,3]:
  #
  #   public   /24 at offsets 0..2      10.10.0.0/24,   10.10.1.0/24
  #   private  /22 at offsets 1..3      10.10.4.0/22,   10.10.8.0/22
  #   isolated /24 at offsets 100..102  10.10.100.0/24, 10.10.101.0/24
  #
  # Public sits inside the /22 block at offset 0, which is deliberately left
  # unused by the private tier.
  public_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 6, i + 1)]
  isolated_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}
