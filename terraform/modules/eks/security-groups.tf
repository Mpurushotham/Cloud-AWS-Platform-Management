resource "aws_security_group" "cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  # The control plane needs to reach node kubelets and AWS APIs over HTTPS.
  # Allowing every port and protocol to 0.0.0.0/0 grants far more than that.
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS APIs and node kubelets"
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-eks-cluster-sg" })
}
