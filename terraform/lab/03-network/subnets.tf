# Three subnet tiers, matching the production design:
#
#   public   — internet-facing load balancers only
#   private  — application workloads; egress via NAT gateway when enabled
#   isolated — databases and caches; no route off the VPC at all

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Never auto-assign. A public IPv4 address is billed hourly, and load
  # balancers bring their own.
  map_public_ip_on_launch = false

  tags = {
    Name                     = "${local.name_prefix}-public-${count.index + 1}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${local.name_prefix}-private-${count.index + 1}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "isolated" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.isolated_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-isolated-${count.index + 1}"
    Tier = "isolated"
  }
}

# Named group for RDS and ElastiCache to land in, so that a database cannot be
# placed in a routable subnet by accident.
resource "aws_db_subnet_group" "isolated" {
  name = "${local.name_prefix}-isolated"
  # ASCII only: the RDS API rejects non-ASCII characters in this field.
  description = "Isolated subnets for databases - no route to the internet"
  subnet_ids  = aws_subnet.isolated[*].id

  tags = { Name = "${local.name_prefix}-isolated-db-subnet-group" }
}
