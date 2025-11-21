variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "hotel"
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_a" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_b" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_a" {
  type    = string
  default = "10.0.3.0/24"
}

variable "private_subnet_b" {
  type    = string
  default = "10.0.4.0/24"
}

# ECR
variable "ecr_repo_name" {
  type    = string
  default = "hotel"
}

variable "app_image" {
  type    = string
  default = "048058681474.dkr.ecr.eu-central-1.amazonaws.com/hotel:v1"

}

# RDS
variable "db_identifier" {
  type        = string
  description = "The RDS instance identifier"
}

variable "db_name" {
  type    = string
  default = "bluebirdhotel"
}

variable "db_username" {
  type    = string
  default = "bluebird_user"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "password"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

# EKS
variable "eks_node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "hotel_namespace" {
  type        = string
  default     = "hotel-app"
  description = "Kubernetes namespace to deploy the hotel application into."
}
