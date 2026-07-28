data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_eks_cluster" "main" {
  #checkov:skip=CKV_AWS_39:Public endpoint is prod-disabled and non-prod is restricted by var.public_access_cidrs, which rejects 0.0.0.0/0. See ADR-0010
  #checkov:skip=CKV_AWS_38:As above -- the allow-list variable forbids 0.0.0.0/0 by validation
  name     = "${var.project}-${var.environment}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.environment != "prod" ? true : false
    security_group_ids      = [aws_security_group.cluster.id]

    # ADR-0010 permits a public endpoint outside production only when it is
    # restricted by CIDR. Without this the endpoint was reachable from
    # 0.0.0.0/0 and protected by authentication alone.
    public_access_cidrs = var.environment != "prod" ? var.public_access_cidrs : null
  }

  encryption_config {
    provider { key_arn = var.kms_key_arn }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_controller,
  ]
}

resource "aws_iam_role" "cluster" {
  name = "${var.project}-${var.environment}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "vpc_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
