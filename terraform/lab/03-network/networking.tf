resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

# ── Default resource lockdown ─────────────────────────────────────────────────
# Every VPC ships with a default security group and NACL that allow more than
# they should. Adopting them into Terraform with no rules turns them into
# deny-all, so that a resource launched without an explicit security group is
# isolated rather than reachable.

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # No ingress or egress blocks: this is an intentional deny-all.

  tags = { Name = "${local.name_prefix}-default-sg-LOCKED" }
}

resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  # Subnets are associated with the tier NACLs in rules.tf, so this one should
  # never be in the path of real traffic. It is locked down regardless.

  tags = { Name = "${local.name_prefix}-default-nacl-LOCKED" }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  # No routes: a subnet that somehow lands on the main route table gets nowhere.

  tags = { Name = "${local.name_prefix}-default-rt-LOCKED" }
}

# ── NAT gateways — disabled in the lab ────────────────────────────────────────
# Guarded by enable_nat_gateway so the production shape stays visible in code
# without being billed for. Since February 2024 every public IPv4 address is
# charged hourly whether or not it is attached, so the Elastic IP is not free
# either.

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? var.az_count : 0

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "${local.name_prefix}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? var.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]

  tags = { Name = "${local.name_prefix}-natgw-${count.index + 1}" }
}
