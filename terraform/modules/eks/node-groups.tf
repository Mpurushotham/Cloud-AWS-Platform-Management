resource "aws_iam_role" "nodes" {
  name = "${var.project}-${var.environment}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "groups" {
  for_each = var.node_group_configs

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.environment}-${each.key}"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [each.value.instance_type]
  capacity_type  = lookup(each.value, "capacity_type", "ON_DEMAND")

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config { max_unavailable = 1 }

  launch_template {
    id      = aws_launch_template.nodes[each.key].id
    version = aws_launch_template.nodes[each.key].latest_version
  }

  tags = merge(local.common_tags, { NodeGroup = each.key })

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

resource "aws_launch_template" "nodes" {
  for_each = var.node_group_configs

  name_prefix = "${var.project}-${var.environment}-${each.key}-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.kms_key_arn
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { NodeGroup = each.key })
  }
}
