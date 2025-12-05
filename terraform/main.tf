
# vpc
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-sandbox-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.2.0/24", "10.0.3.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Name        = "eks-sandbox-vpc"
    Terraform   = "true"
    Environment = "dev"
  }
}

# eks cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  name               = "eks-sandbox"
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

  kubernetes_version = "1.33"

  subnet_ids   = module.vpc.private_subnets
  desired_size = 1
  max_size     = 2
  min_size     = 1

  instance_types = ["t3.nano"]

  cluster_service_cidr = module.eks.cluster_service_cidr

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

  security_group_egress_rules = {
    all = {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
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
      identifiers = ["ec2.amazonaws.com"]
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

# Attach ALB target group to ASG of EKS Node Group
resource "aws_autoscaling_attachment" "eks_node_group_attachment" {
  autoscaling_group_name = module.eks_node_group.node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.alb_tg_to_ng.arn
}

# ALB
module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "eks-sandbox-alb"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_groups = [aws_security_group.alb_sg.id]

  enable_deletion_protection = false

  tags = {
    Name        = "eks-sandbox-alb"
    Terraform   = "true"
    Environment = "dev"
  }
}

# ALB Listeners
resource "aws_lb_listener" "http" {
  load_balancer_arn = module.alb.arn
  port              = 80
  protocol          = "HTTP"

  # For HTTP-only: Forward directly to target group
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg_to_ng.arn
  }

  # For HTTPS: Redirect HTTP to HTTPS (uncomment when HTTPS is enabled)
  # default_action {
  #   type = "redirect"
  #   redirect {
  #     port        = "443"
  #     protocol    = "HTTPS"
  #     status_code = "HTTP_301"
  #   }
  # }
}

# HTTPS Listener (TODO: Uncomment this when enabling HTTPS)
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = module.alb.arn
#   port              = 443
#   protocol          = "HTTPS"
#
#   ssl_policy      = "ELBSecurityPolicy-2016-08"
#   certificate_arn = aws_acm_certificate_validation.public_cert.certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.alb_tg_to_ng.arn
#   }
# }

# target group for listener of ALB
resource "aws_lb_target_group" "alb_tg_to_ng" {
  name        = "eks-sandbox-alb-tg"
  port        = 30080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "eks-sandbox-alb-tg"
    Terraform   = "true"
    Environment = "dev"
  }
}

# ACM Public Certificate for ALB HTTPS (TODO: Uncomment this when enabling HTTPS)
# resource "aws_acm_certificate" "public_cert" {
#   domain_name       = module.zone.name
#   validation_method = "DNS"
#
#   lifecycle {
#     create_before_destroy = true
#   }
#
#   tags = {
#     Name        = "eks-sandbox-alb-cert"
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }

# ACM Certificate validation records (TODO: Uncomment this when enabling HTTPS)
# resource "aws_route53_record" "acm_validation_dns_record" {
#   for_each = {
#     for dvo in aws_acm_certificate.public_cert.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }
#
#   zone_id = module.zone.id
#   name    = each.value.name
#   type    = each.value.type
#   records = [each.value.record]
#   ttl     = 60
# }

# Wait for certificate validation to complete (TODO: Uncomment this when enabling HTTPS)
# resource "aws_acm_certificate_validation" "public_cert" {
#   certificate_arn         = aws_acm_certificate.public_cert.arn
#   validation_record_fqdns = [for record in aws_route53_record.acm_validation_dns_record : record.fqdn]
# }

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

  # HTTPS ingress rule (TODO: Uncomment this when enabling HTTPS)
  # ingress {
  #   description = "Allow HTTPS traffic"
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

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

# Route53 Zone (TODO: Uncomment this when enabling HTTPS with custom domain)
# module "zone" {
#   source = "terraform-aws-modules/route53/aws"
#
#   name = "eks-sandbox.com"
#
#   records = {
#     app = {
#       type = "A"
#       name = "app"
#       alias = {
#         name    = module.alb.dns_name
#         zone_id = module.alb.zone_id
#       }
#     }
#   }
#
#   tags = {
#     Name        = "eks-sandbox-zone"
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }

# Domain Registration (TODO: Uncomment this when enabling HTTPS with domain registration)
# Note: Costs $13/year, requires us-east-1 provider, and cannot be easily deleted
# resource "aws_route53domains_registered_domain" "main" {
#   domain_name = "eks-sandbox.com"
#
#   # Contact information (required for domain registration)
#   admin_contact {
#     contact_type   = "PERSON"
#     first_name     = "Your"
#     last_name      = "Name"
#     email          = "your-email@example.com"
#     phone_number   = "+81.9012345678"  # Format: +CountryCode.PhoneNumber
#     address_line_1 = "1-1-1 Chiyoda"
#     city           = "Tokyo"
#     country_code   = "JP"
#     zip_code       = "100-0001"
#   }
#
#   registrant_contact {
#     contact_type   = "PERSON"
#     first_name     = "Your"
#     last_name      = "Name"
#     email          = "your-email@example.com"
#     phone_number   = "+81.9012345678"
#     address_line_1 = "1-1-1 Chiyoda"
#     city           = "Tokyo"
#     country_code   = "JP"
#     zip_code       = "100-0001"
#   }
#
#   tech_contact {
#     contact_type   = "PERSON"
#     first_name     = "Your"
#     last_name      = "Name"
#     email          = "your-email@example.com"
#     phone_number   = "+81.9012345678"
#     address_line_1 = "1-1-1 Chiyoda"
#     city           = "Tokyo"
#     country_code   = "JP"
#     zip_code       = "100-0001"
#   }
#
#   # Auto-renew domain annually
#   auto_renew = true
#
#   tags = {
#     Name        = "eks-sandbox-domain"
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }

# ecr repository
resource "aws_ecr_repository" "ecr_repository" {
  name = "eks-sandbox-ecr-repository"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "eks-sandbox-ecr-repository"
    Terraform   = "true"
    Environment = "dev"
  }
}

# vpc endpoint for accessing ECR from private subnet
resource "aws_vpc_endpoint" "vpc_endpoint_for_ecr_api" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.ap-northeast-1.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  private_dns_enabled = true

  tags = {
    Name        = "eks-sandbox-ecr-api-endpoint"
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_vpc_endpoint" "vpc_endpoint_for_ecr_dkr" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.ap-northeast-1.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  private_dns_enabled = true

  tags = {
    Name        = "eks-sandbox-ecr-dkr-endpoint"
    Terraform   = "true"
    Environment = "dev"
  }
}

# vpc endpoint for accessing S3 from private subnet
resource "aws_vpc_endpoint" "vpc_endpoint_for_s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name        = "eks-sandbox-s3-endpoint"
    Terraform   = "true"
    Environment = "dev"
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vpc-endpoint-sg"
    Terraform   = "true"
    Environment = "dev"
  }
}

# IAM role for developer
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

resource "aws_iam_role_policy_attachment" "developer_ecr_fullaccess" {
  role       = aws_iam_role.developer_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# ReadOnlyAccess provides read permissions for all AWS services
# Including EKS, EC2, ELB, VPC, etc. for infrastructure verification
resource "aws_iam_role_policy_attachment" "developer_readonly" {
  role       = aws_iam_role.developer_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
