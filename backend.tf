terraform {
  backend "s3" {
    bucket         = "my-terraform-state-048058"
    key            = "hotel/eks-rds/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "prod"
    encrypt        = true
  }
}
