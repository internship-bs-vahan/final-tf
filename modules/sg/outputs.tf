output "eks_cluster_sg_id" {
  value = aws_security_group.eks_cluster.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
