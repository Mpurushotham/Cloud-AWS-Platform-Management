locals {
  addons = {
    vpc-cni            = { version = "v1.18.1-eksbuild.1" }
    coredns            = { version = "v1.11.1-eksbuild.9" }
    kube-proxy         = { version = "v1.30.0-eksbuild.3" }
    aws-ebs-csi-driver = { version = "v1.32.0-eksbuild.1" }
  }
}

resource "aws_eks_addon" "addons" {
  for_each = local.addons

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = each.key
  addon_version            = each.value.version
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}
