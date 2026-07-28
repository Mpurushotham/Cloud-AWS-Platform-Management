# Security groups and NACLs.
#
# Per the project convention, every rule is a separate aws_security_group_rule
# resource rather than an inline ingress/egress block. Inline blocks are
# authoritative — Terraform silently removes any rule it does not know about,
# which turns an out-of-band emergency fix into an outage on the next apply.

# ── Security groups ───────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Network layer applies before compute; consumed by later layers
  name        = "${local.name_prefix}-sg-alb"
  description = "Internet-facing load balancer"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-alb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Network layer applies before compute; consumed by later layers
  name        = "${local.name_prefix}-sg-app"
  description = "Application workloads in the private tier"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-app" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "data" {
  #checkov:skip=CKV2_AWS_5:Network layer applies before compute; consumed by later layers
  name        = "${local.name_prefix}-sg-data"
  description = "Databases and caches in the isolated tier"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-data" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-sg-vpc-endpoints"
  description = "Interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-vpc-endpoints" }

  lifecycle {
    create_before_destroy = true
  }
}

# ALB: HTTPS from the internet. No port 80 — redirect happens at the listener.
resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS from the internet"
}

resource "aws_security_group_rule" "alb_egress_app" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.app.id
  description              = "Forward to application tier"
}

# App: only from the load balancer, never from a CIDR.
resource "aws_security_group_rule" "app_ingress_alb" {
  security_group_id        = aws_security_group.app.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.alb.id
  description              = "Application traffic from the load balancer"
}

resource "aws_security_group_rule" "app_egress_data" {
  security_group_id        = aws_security_group.app.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.data.id
  description              = "PostgreSQL to the data tier"
}

resource "aws_security_group_rule" "app_egress_https" {
  security_group_id = aws_security_group.app.id
  type              = "egress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS to AWS service endpoints"
}

# Data: reachable only from the application tier, and egresses nowhere.
resource "aws_security_group_rule" "data_ingress_app" {
  security_group_id        = aws_security_group.data.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.app.id
  description              = "PostgreSQL from the application tier"
}

# VPC endpoints: HTTPS from inside the VPC only.
resource "aws_security_group_rule" "vpce_ingress_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.vpc_cidr]
  description       = "HTTPS from within the VPC"
}

# ── Network ACLs ──────────────────────────────────────────────────────────────
# NACLs are stateless, so both directions need rules, and ephemeral return
# traffic must be allowed explicitly. They are a coarse second layer beneath
# security groups, not a replacement for them.

resource "aws_network_acl" "isolated" {
  #checkov:skip=CKV2_AWS_1:Attached via the subnet_ids argument on this resource
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.isolated[*].id

  tags = { Name = "${local.name_prefix}-nacl-isolated" }
}

resource "aws_network_acl_rule" "isolated_ingress_vpc" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "isolated_egress_ephemeral" {
  network_acl_id = aws_network_acl.isolated.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

# Everything not matched above is denied by the implicit rule 32767.
