# Three subnet tiers across var.az_count AZs:
# - Public  (24-bit): load balancers only, no auto-assign public IP
# - Private (22-bit): workloads (EKS nodes, ECS tasks), egress via NAT GW
# - Isolated (24-bit): databases (RDS, ElastiCache), no route to internet

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                     = "${var.project}-${var.environment}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  })
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 2, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name                              = "${var.project}-${var.environment}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
    Tier                              = "private"
  })
}

resource "aws_subnet" "isolated" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 12)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-isolated-${count.index + 1}"
    Tier = "isolated"
  })
}
