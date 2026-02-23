# Dev Environment Configuration
# Safe to commit - no secrets here

aws_region  = "eu-west-2"
environment = "dev"

# VPC Configuration
vpc_cidr                 = "10.0.0.0/16"
public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]

enable_nat_gateway = true
single_nat_gateway = true  # Cost savings for dev

# RDS Configuration
db_name                    = "devappdb"
db_username                = "dbadmin"
db_instance_class          = "db.t3.micro"
db_allocated_storage       = 20
db_multi_az                = false
db_backup_retention_period = 7
db_port = 5432

# EC2/ASG Configuration
instance_type        = "t3.micro"
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 2