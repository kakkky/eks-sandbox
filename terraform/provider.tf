provider "aws" {
  region  = "ap-northeast-1"
  profile = "default"
  # assume_role {
  #   role_arn = aws_iam_role.developer_role.arn
  # }
}
