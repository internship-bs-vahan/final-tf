########################################
# Data & locals
########################################

data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

########################################
# VPC
########################################

module "vpc" {
  source               = "./modules/vpc"
  name                 = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = [var.public_subnet_a, var.public_subnet_b]
  private_subnet_cidrs = [var.private_subnet_a, var.private_subnet_b]
  azs                  = local.azs
}

########################################
# Security Groups
########################################

module "sg" {
  source = "./modules/sg"
  vpc_id = module.vpc.vpc_id
}

########################################
# RDS + Secrets Manager
########################################

module "rds" {
  source = "./modules/rds"

  name_prefix        = var.name_prefix
  db_identifier      = var.db_identifier
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.sg.rds_sg_id

  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_instance_class = var.db_instance_class
}



########################################
# ECR (declared even if repo already exists)
########################################

module "ecr" {
  source    = "./modules/ecr"
  repo_name = var.ecr_repo_name
}

########################################
# EKS IAM Roles (cluster + node)
########################################

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM Session Manager for worker nodes
resource "aws_iam_role_policy_attachment" "eks_node_AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

########################################
# EKS Cluster & Node Group
########################################

resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids = concat(
      module.vpc.public_subnet_ids,
      module.vpc.private_subnet_ids
    )
    security_group_ids = [module.sg.eks_cluster_sg_id]
  }

  timeouts {
    delete = "30m"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-eks-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = module.vpc.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = [var.eks_node_instance_type]

  timeouts {
    delete = "60m"
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_AmazonSSMManagedInstanceCore
  ]
}

########################################
# EKS OIDC Provider (for IRSA)
########################################

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd10df6"]
}

########################################
# IAM Policy & Role for Hotel App (IRSA -> Secrets Manager)
########################################

resource "aws_iam_policy" "hotel_app_secrets_policy" {
  name        = "${var.name_prefix}-secretsmanager-policy"
  description = "Allow hotel app to read RDS secret from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = module.rds.db_secret_arn
      }
    ]
  })
}

resource "aws_iam_role" "hotel_app_irsa_role" {
  name = "${var.name_prefix}-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:hotel-app:hotel-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "hotel_app_irsa_policy_attach" {
  role       = aws_iam_role.hotel_app_irsa_role.name
  policy_arn = aws_iam_policy.hotel_app_secrets_policy.arn
}

########################################
# NGINX Ingress Controller via Helm (NLB)
########################################

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  timeout = 900  # 15 minutes

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
      }
    })
  ]

  depends_on = [
    aws_eks_node_group.this
  ]
}


########################################
# Namespace & Service Account for Hotel App
########################################

resource "kubernetes_service_account" "hotel_sa" {
  metadata {
    name      = "hotel-sa"
    namespace = var.hotel_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.hotel_app_irsa_role.arn
    }
  }

}

########################################
# Kubernetes Secret with DB configuration
########################################

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name      = "db-credentials"
    namespace = var.hotel_namespace
  }

  data = {
    DB_HOST     = module.rds.db_endpoint
    DB_NAME     = var.db_name
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
  }

  type = "Opaque"

}


########################################
# Hotel Application Deployment
########################################

resource "kubernetes_deployment" "hotel" {
  metadata {
    name      = "hotel-app"
    namespace = var.hotel_namespace
    labels = {
      app = "hotel-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hotel-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "hotel-app"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.hotel_sa.metadata[0].name

        container {
          name  = "hotel"
          image = var.app_image

          port {
            container_port = 80
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.db_credentials.metadata[0].name
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}


########################################
# Service & Ingress for Hotel App
########################################

resource "kubernetes_service" "hotel" {
  metadata {
    name      = "hotel-service"
    namespace = var.hotel_namespace
    labels = {
      app = "hotel-app"
    }
  }

  spec {
    selector = {
      app = "hotel-app"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

}


resource "kubernetes_ingress_v1" "hotel" {
  metadata {
    name      = "hotel-ingress"
    namespace = var.hotel_namespace
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.hotel.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
