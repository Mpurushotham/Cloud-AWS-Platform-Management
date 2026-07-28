# Three subnet tiers across var.az_count AZs, for a /16 VPC CIDR:
#
#   Public   /24  cidrsubnet(cidr, 8, i)        load balancers only
#   Private  /22  cidrsubnet(cidr, 6, i + 1)    EKS nodes, ECS tasks
#   Isolated /24  cidrsubnet(cidr, 8, i + 100)  RDS, ElastiCache
#
# The offsets are chosen so the tiers cannot overlap at any az_count up to 3.
# Public occupies the /22 block at offset 0, which the private tier skips.
#
# The previous arithmetic (4,i / 2,i+1 / 4,i+12) placed all three isolated
# subnets inside private[2] — 10.x.192.0/20 falls within 10.x.192.0/18 — so AWS
# rejected the overlapping CIDR and the module could not apply. The comments
# also described /24 and /22 sizes that the expressions did not produce.

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
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
  cidr_block        = cidrsubnet(var.vpc_cidr, 6, count.index + 1)
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
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 100)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-isolated-${count.index + 1}"
    Tier = "isolated"
  })
}

# Overlap guard.
#
# Comparing CIDR strings is not sufficient — the original bug was containment,
# not equality: a /24 inside a /18 is a distinct string and still an overlap.
# Terraform has no CIDR-containment function, so each subnet is expressed as a
# half-open interval measured in /24 blocks from the base of the VPC, where
# overlap is ordinary integer arithmetic.
#
# For a /16 VPC there are 256 such blocks:
#   public   /24 at offset i        -> [i,        i + 1)
#   private  /22 at offset i + 1    -> [(i+1)*4,  (i+1)*4 + 4)
#   isolated /24 at offset i + 100  -> [100 + i,  100 + i + 1)

locals {
  _subnet_intervals = concat(
    [for i in range(var.az_count) : { start = i, end = i + 1 }],
    [for i in range(var.az_count) : { start = (i + 1) * 4, end = (i + 1) * 4 + 4 }],
    [for i in range(var.az_count) : { start = 100 + i, end = 100 + i + 1 }],
  )

  _subnet_overlaps = [
    for pair in setproduct(
      range(length(local._subnet_intervals)),
      range(length(local._subnet_intervals))
    ) : pair
    if pair[0] < pair[1]
    && local._subnet_intervals[pair[0]].start < local._subnet_intervals[pair[1]].end
    && local._subnet_intervals[pair[1]].start < local._subnet_intervals[pair[0]].end
  ]
}

resource "terraform_data" "subnet_cidr_guard" {
  lifecycle {
    precondition {
      condition     = tonumber(split("/", var.vpc_cidr)[1]) == 16
      error_message = "The subnet arithmetic in subnets.tf is derived for a /16 VPC. Recompute the offsets before using another prefix length."
    }

    precondition {
      condition     = length(local._subnet_overlaps) == 0
      error_message = "Subnet ranges overlap. AWS rejects overlapping CIDRs part-way through the apply, leaving a half-built VPC. Fix the offsets in subnets.tf."
    }
  }
}
