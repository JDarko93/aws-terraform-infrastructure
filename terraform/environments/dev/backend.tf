
# Terraform State Backend Configuration
# Uncomment and configure after creating S3 bucket and DynamoDB table

# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"  # CHANGE THIS
#     key            = "dev/terraform.tfstate"
#     region         = "eu-west-2"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }

# To create the S3 bucket and DynamoDB table, run:
# aws s3api create-bucket --bucket your-terraform-state-bucket --region eu-west-2
# aws dynamodb create-table \
#   --table-name terraform-state-lock \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST \
#   --region eu-west-2