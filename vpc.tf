module "aws_vpc" {
  source          = "github.com/erozedguy/AWS-VPC-terraform-module.git"
  networking      = var.networking
  security_groups = var.security_groups
}
