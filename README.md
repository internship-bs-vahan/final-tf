1. Overview

This project deploys a fully automated, production-grade AWS infrastructure for the Hotel Application, using Terraform, Kubernetes, and AWS managed services.

Core technologies

Terraform

AWS VPC (public + private subnets, NAT)

RDS MySQL

AWS Secrets Manager

AWS ECR

Amazon EKS (v1.29)

NGINX Ingress Controller (NLB)

IRSA (IAM Roles for Service Accounts)

Kubernetes Deployment, Service, Ingress

SSM Session Manager

2. High-Level Architecture


                         ┌────────────────────────────┐
                         │        Internet User       │
                         └──────────────┬─────────────┘
                                        │
                              (HTTPS/NLB Ingress)
                                        │
                  ┌─────────────────────▼─────────────────────┐
                  │       AWS Network Load Balancer (NLB)     │
                  └─────────────────────┬─────────────────────┘
                                        │
                               Routes to Ingress Controller
                                        │
                ┌───────────────────────▼────────────────────────┐
                │        EKS Cluster (hotel-eks, v1.29)          │
                │Namespace: hotel-app   ServiceAccount: hotel-sa │
                └───────────────────────┬────────────────────────┘
                                        │
                     IRSA → Secrets Manager Permission
                                        │
                          ┌─────────────▼──────────────┐
                          │  Hotel App Pod (Docker)    │
                          │ Env from K8s Secret        │
                          └──────────────┬─────────────┘
                                         │ Connects
                                         ▼
                               RDS MySQL (private subnet)


3. AWS Components Used
3.1 VPC Module

Creates:

1 VPC (10.0.0.0/16)

2 public subnets

2 private subnets

NAT Gateway (1)

Internet Gateway

Public & Private Route Tables

3.2 Security Groups

eks_cluster_sg

rds_sg (only allows MySQL traffic from private subnets/EKS)

3.3 RDS MySQL

Instance identifier: bluebird-db

Database name: bluebirdhotel

Credentials stored securely in AWS Secrets Manager

Private subnet deployment (not publicly accessible)

3.4 ECR

Stores hotel app image: 048058681474.dkr.ecr.eu-central-1.amazonaws.com/hotel:v1

3.5 EKS Cluster

Kubernetes version: 1.29

Managed Node Group (t3.small)

Private subnet only

SSM enabled

3.6 IRSA

A Kubernetes service account (hotel-sa) assumes a dedicated IAM role to read secrets.

3.7 NGINX Ingress Controller

Installed through Helm

Exposed via Network Load Balancer

Publicly accessible

4. Terraform Structure

root/
│── main.tf
│── providers.tf
│── variables.tf
│── outputs.tf
│── backend.tf
│── terraform.tfvars
│── modules/
│   ├── vpc/
│   ├── sg/
│   ├── rds/
│   ├── ecr/

5. Backend Configuration

Using:

S3 bucket: my-terraform-state-048058

DynamoDB table: prod (Partition key: LockID)

Backend is stored inside providers.tf

6. Sensitive Data Handling

Database username, password stored in AWS Secrets Manager
EKS pods retrieve secrets using IRSA
Kubernetes secret holds DB config inside cluster

7. Deployment Flow
terraform init
terraform validate
terraform plan
terraform apply

8. Post-Deployment Steps
Run these 2 commands below:

aws eks update-kubeconfig --region eu-central-1 --name hotel-eks

kubectl create namespace hotel-app

and re-run
terraform apply

kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo

Open DNS hostname in browser

9. Destroying Infrastructure
terraform destroy