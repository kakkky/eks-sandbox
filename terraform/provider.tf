provider "aws" {
  region = "ap-northeast-1"
}

# us-east-1 provider (Required for Route53 domain registration)
# Uncomment when using aws_route53domains_registered_domain resource
# provider "aws" {
#   alias  = "us-east-1"
#   region = "us-east-1"
# }
