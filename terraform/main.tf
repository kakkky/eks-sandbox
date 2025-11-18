
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


  eks_managed_node_groups = {
    eks_node_group = {
      desired_capacity = 2
      max_capacity     = 2
      min_capacity     = 2

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
    }
  }

  tags = {
    Name        = "eks-sandbox-cluster"
    Terraform   = "true"
    Environment = "dev"
  }
}


