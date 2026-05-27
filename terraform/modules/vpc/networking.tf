# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpc" })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project}-${var.environment}-igw" })
}

# ── Elastic IPs for NAT Gateways (one per AZ) ────────────────────────────────
resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.project}-${var.environment}-nat-eip-${count.index + 1}" })

  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateways (one per AZ for AZ-resilient private egress) ────────────────
resource "aws_nat_gateway" "main" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-natgw-${count.index + 1}" })

  depends_on = [aws_internet_gateway.main]
}

# ── Default Resources Lockdown ────────────────────────────────────────────────
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # No ingress or egress rules — deny all traffic on default SG
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-default-sg-LOCKED" })
}

resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-default-nacl-LOCKED" })
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
    Owner       = var.owner
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }
