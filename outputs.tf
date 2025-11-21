output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "rds_endpoint" {
  value       = module.rds.db_endpoint
  description = "RDS endpoint hostname"
}

output "rds_secret_arn" {
  value       = module.rds.db_secret_arn
  description = "Secrets Manager ARN for DB creds"
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}