provider "aws" {
  region = var.aws_region
}

# Load EKS metadata after cluster creation
data "aws_eks_cluster" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [aws_eks_node_group.this]
}

data "aws_eks_cluster_auth" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [aws_eks_node_group.this]
}


# Kubernetes provider
provider "kubernetes" {
  host  = data.aws_eks_cluster.this.endpoint
  token = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.this.certificate_authority[0].data
  )
}

# Helm provider MUST specify the kubernetes block under "provider_settings"
# This works for ALL versions and removes the VSCode error.
provider "helm" {
  kubernetes {
    host  = data.aws_eks_cluster.this.endpoint
    token = data.aws_eks_cluster_auth.this.token
    cluster_ca_certificate = base64decode(
      data.aws_eks_cluster.this.certificate_authority[0].data
    )
  }
}
