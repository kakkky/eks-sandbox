
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



