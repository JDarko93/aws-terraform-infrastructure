terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AWS-Terraform-Infrastructure"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data source for latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr                 = var.vpc_cidr
  environment              = var.environment
  availability_zones       = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  enable_nat_gateway       = var.enable_nat_gateway
  single_nat_gateway       = var.single_nat_gateway
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"

  vpc_id      = module.vpc.vpc_id
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  environment = var.environment
}

# RDS Module
module "rds" {
  source = "../../modules/rds"

  environment             = var.environment
  db_subnet_ids           = module.vpc.private_db_subnet_ids
  security_group_ids      = [module.security_groups.db_security_group_id]
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
}

# ALB Module
module "alb" {
  source = "../../modules/alb"

  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_security_group_id]
  health_check_path  = "/health"
}

# ASG Module
module "asg" {
  source = "../../modules/asg"

  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_app_subnet_ids
  security_group_ids        = [module.security_groups.app_security_group_id]
  target_group_arns         = [module.alb.target_group_arn]
  instance_type             = var.instance_type
  ami_id                    = data.aws_ami.ubuntu.id
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  iam_instance_profile_name = module.iam.ec2_instance_profile_name
  db_endpoint               = module.rds.db_instance_address
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  port                   = var.port

  depends_on = [module.rds]
}

# Monitoring Module
module "monitoring" {
  source = "../../modules/monitoring"

  environment            = var.environment
  alb_arn                = split("/", module.alb.alb_arn)[1]
  target_group_arn       = split(":", module.alb.target_group_arn)[5]
  autoscaling_group_name = module.asg.autoscaling_group_name
  db_instance_id         = module.rds.db_instance_id
  alert_email            = var.alert_email
}