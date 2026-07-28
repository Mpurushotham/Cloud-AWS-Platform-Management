# ── Public tier ───────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private tier ──────────────────────────────────────────────────────────────
# One route table per AZ so that, when NAT is enabled, each AZ egresses through
# its own gateway and an AZ failure cannot take down the others.
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rt-private-${count.index + 1}" }
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? var.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── Isolated tier ─────────────────────────────────────────────────────────────
# Deliberately has no default route in any configuration. Reachability is
# limited to the VPC's local route plus the gateway endpoints below.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rt-isolated" }
}

resource "aws_route_table_association" "isolated" {
  count = var.az_count

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}

# ── Gateway VPC endpoints ─────────────────────────────────────────────────────
# S3 and DynamoDB gateway endpoints are free and are what let private and
# isolated subnets reach those services with no NAT gateway in the path. They
# work by injecting prefix-list routes into the associated route tables.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id],
  )

  tags = { Name = "${local.name_prefix}-vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.isolated.id],
  )

  tags = { Name = "${local.name_prefix}-vpce-dynamodb" }
}

# ── Interface VPC endpoints — disabled in the lab ─────────────────────────────
# The production design specifies ten of these. Each bills hourly per AZ, so
# they are gated behind a flag rather than removed, keeping the intended shape
# reviewable in code.

locals {
  interface_endpoint_services = var.enable_interface_endpoints ? toset([
    "ecr.api",
    "ecr.dkr",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "secretsmanager",
    "sts",
    "logs",
    "kms",
    "xray",
  ]) : toset([])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-${replace(each.value, ".", "-")}" }
}
