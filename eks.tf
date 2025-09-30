provider "aws" {
  region     = "us-east-2"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks-cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks-cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks-cluster.name
}

# IAM Roles
resource "aws_iam_role" "EKSClusterRole" {
  name = "EKSClusterRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "NodeGroupRole" {
  name = "EKSNodeGroupRoles"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM Policy Attachments
resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.EKSClusterRole.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.NodeGroupRole.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.NodeGroupRole.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.NodeGroupRole.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks-cluster" {
  name     = "ravi-eks-cluster"
  role_arn = aws_iam_role.EKSClusterRole.arn
  version  = "1.29"

  vpc_config {
    subnet_ids         = flatten([module.aws_vpc.public_subnets_id, module.aws_vpc.private_subnets_id])
    security_group_ids = flatten(module.aws_vpc.security_groups_id)
  }

  depends_on = [aws_iam_role_policy_attachment.AmazonEKSClusterPolicy]
}

# EKS Node Group
resource "aws_eks_node_group" "node-ec2" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "t3_micro-node_group"
  node_role_arn   = aws_iam_role.NodeGroupRole.arn
  subnet_ids      = flatten(module.aws_vpc.private_subnets_id)

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  ami_type       = "AL2_x86_64"
  instance_types = ["t3.small"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy
  ]
}

# Update kubeconfig locally
resource "null_resource" "kubeconfig" {
  depends_on = [aws_eks_cluster.eks-cluster]

  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig \
        --region us-east-2 \
        --name ${aws_eks_cluster.eks-cluster.name}
    EOT
  }
}

# aws-auth ConfigMap for node access
#resource "kubernetes_config_map" "aws_auth" {
#  metadata {
#    name      = "aws-auth"
#    namespace = "kube-system"
#  }
#  data = {
#    mapRoles = jsonencode([
#      {
#        rolearn  = aws_iam_role.NodeGroupRole.arn
#        username = "system:node:{{EC2PrivateDNSName}}"
#        groups   = [
#          "system:bootstrappers",
#          "system:nodes"
#        ]
#      }
#    ])
#  }

#  depends_on = [
#    aws_eks_node_group.node-ec2,
#    null_resource.kubeconfig
#  ]
#}

