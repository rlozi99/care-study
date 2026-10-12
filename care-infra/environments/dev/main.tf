terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {           # data "tls_certificate"를 쓰기 위해 필요
      source  = "hashicorp/tls"
      version = "~> 4.0"
}
  }
  # Configure the backend to store the Terraform state in an S3 bucket
  backend "s3" {
    bucket         = "<STATE_BUCKET>"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "<LOCK_TABLE>"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name         = "care-dev"
  azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
}

module "eks" {
  source = "../../modules/eks"

  project_name       = "care-dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  admin_cidr         = var.admin_cidr
  node_instance_type = "t3.small"
  node_desired_size  = 3
  node_min_size      = 1
  node_max_size      = 5
}

module "ecr" {
  source = "../../modules/ecr"

  project_name = "care"
}

# 모듈 안의 output은 자동으로 밖에 안나가기 때문에 dec/main에서 한 번 더 꺼내줘야 한다.
output "cluster_name" { value = module.eks.cluster_name }
output "repository_url" { value = module.ecr.repository_url }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.oidc_provider_url }
output "lb_controller_role_arn" { value = module.eks.lb_controller_role_arn }