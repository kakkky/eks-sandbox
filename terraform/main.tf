
# vpc
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-sandbox-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-1a"]
  public_subnets  = ["10.0.0.0/24"]
  private_subnets = ["10.0.1.0/24"]

  tags = {
    Name        = "eks-sandbox-vpc"
    Terraform   = "true"
    Environment = "dev"
  }
}

# eks cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "1.21"

  name               = "eks-sandbox-cluster"
  kubernetes_version = "1.33"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true

  access_entries = {
    developer = {
      principal_arn     = aws_iam_role.developer_role.arn
      kubernetes_groups = []

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type       = "cluster"
            namespaces = []
          }
        }
      }
    }
  }

  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  tags = {
    Name        = "eks-sandbox-cluster"
    Terraform   = "true"
    Environment = "dev"
  }
}

# node group
module "eks_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name         = "eks-sandbox-node-group"
  cluster_name = module.eks.cluster_name

  subnet_ids   = module.vpc.private_subnets
  desired_size = 2
  max_size     = 3
  min_size     = 1

  instance_types = ["t3.nano"]

  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_node_group_role.arn

  create_security_group = true
  security_group_ingress_rules = {
    alb_nodeport = {
      description                  = "Allow ALB to communicate with Node Group"
      from_port                    = 30000
      to_port                      = 32767
      protocol                     = "tcp"
      referenced_security_group_id = aws_security_group.alb_sg.id
    }
  }

  labels = {
    role = "app"
  }

  tags = {
    Name        = "eks-sandbox-node-group"
    Terraform   = "true"
    Environment = "dev"
  }
}

# IAM role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role_policy.json
}

data "aws_iam_policy_document" "eks_cluster_assume_role_policy" {
  statement {
    sid    = "AllowEKSClusterAssumeRole"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# IAM role for EKS Node Group
resource "aws_iam_role" "eks_node_group_role" {
  name               = "eks-node-group-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_group_assume_role_policy.json
}

data "aws_iam_policy_document" "eks_node_group_assume_role_policy" {
  statement {
    sid    = "AllowEKSNodeGroupAssumeRole"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_AmazonEC2ContainerRegistryPullOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}




# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "eks-sandbox-alb-sg"
    Terraform   = "true"
    Environment = "dev"
  }
}

# Route53 Zone
module "zone" {
  source = "terraform-aws-modules/route53/aws"

  name = "eks-sandbox-todo-list.com"

  records = {
    app = {
      type = "A"
      alias = {
        name    = module.alb.dns_name
        zone_id = module.alb.zone_id
      }
    }
  }

  tags = {
    Name        = "eks-sandbox-zone"
    Terraform   = "true"
    Environment = "dev"
  }
}


# IAM role for developer access
resource "aws_iam_role" "developer_role" {
  name               = "developer-role"
  assume_role_policy = data.aws_iam_policy_document.developer_assume_role_policy.json
}

data "aws_iam_policy_document" "developer_assume_role_policy" {
  statement {
    sid    = "AllowAssumeRoleForDeveloper"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::846869429016:user/yuta"]
    }
    actions = ["sts:AssumeRole"]
  }
}
