# Public route table — default route to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rt-public" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables (one per AZ) — default route to NAT GW in same AZ
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rt-private-${count.index + 1}" })
}

resource "aws_route" "private_nat" {
  count                  = var.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Isolated route table — no default route (no internet access)
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rt-isolated" })
}

resource "aws_route_table_association" "isolated" {
  count          = var.az_count
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
