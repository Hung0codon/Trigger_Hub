# EKS Cluster Control Plane IAM Role
resource "aws_iam_role" "cluster" {
  name = "tf1-cdo05-${var.env}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# EKS Cluster Control Plane
resource "aws_eks_cluster" "this" {
  name                      = "tf1-cdo05-${var.env}-eks-cluster"
  role_arn                  = aws_iam_role.cluster.arn
  version                   = "1.30"
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.sg_eks_nodes_id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
  ]

  tags = {
    Name        = "tf1-cdo05-${var.env}-eks-cluster"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# EKS Node Group Worker Nodes IAM Role
resource "aws_iam_role" "node" {
  name = "tf1-cdo05-${var.env}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# Launch Template for EKS Node Group
resource "aws_launch_template" "node" {
  name_prefix   = "tf1-cdo05-${var.env}-eks-node-"
  instance_type = var.instance_types[0]

  vpc_security_group_ids = [
    var.sg_eks_nodes_id,
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                                     = "tf1-cdo05-${var.env}-eks-worker-node"
      Environment                                              = var.env
      Project                                                  = "tf1-cdo05"
      "kubernetes.io/cluster/tf1-cdo05-${var.env}-eks-cluster" = "owned"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EKS Managed Node Group
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "tf1-cdo05-${var.env}-eks-node-group"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    name    = aws_launch_template.node.name
    version = aws_launch_template.node.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = {
    Name        = "tf1-cdo05-${var.env}-eks-node-group"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}

# OIDC Identity Provider (for IRSA)
data "tls_certificate" "this" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.this.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name        = "tf1-cdo05-${var.env}-eks-oidc-provider"
    Environment = var.env
    Project     = "tf1-cdo05"
  }
}
