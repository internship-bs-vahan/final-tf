# Hotel Application Infrastructure on AWS

## 1. Overview

This project provisions a fully automated, production-ready AWS infrastructure for the **Hotel Application**, using **Terraform**, **Amazon EKS**, and other AWS managed services.

The goal is to provide a modular, reproducible setup for running a containerized hotel web application with:

- Isolated networking (public + private subnets)
- Managed Kubernetes (EKS)
- Secure database access (RDS + Secrets Manager + IRSA)
- Production-grade ingress (NGINX Ingress + Network Load Balancer)
- Zero-SSH access via SSM Session Manager

### Core Technologies

- **Terraform**
- **AWS VPC** (public & private subnets, NAT Gateway)
- **Amazon RDS (MySQL)**
- **AWS Secrets Manager**
- **Amazon ECR**
- **Amazon EKS** (v1.29)
- **NGINX Ingress Controller** (via Helm, with NLB)
- **IRSA** (IAM Roles for Service Accounts)
- **Kubernetes** (Deployment, Service, Ingress)
- **AWS Systems Manager Session Manager (SSM)**

---

## 2. High-Level Architecture

```text
                         ┌────────────────────────────┐
                         │        Internet User       │
                         └──────────────┬─────────────┘
                                        │
                              (HTTPS via NLB Ingress)
                                        │
                  ┌─────────────────────▼─────────────────────┐
                  │       AWS Network Load Balancer (NLB)     │
                  └─────────────────────┬─────────────────────┘
                                        │
                               Routes to Ingress Controller
                                        │
                ┌───────────────────────▼────────────────────────┐
                │        EKS Cluster (hotel-eks, v1.29)          │
                │ Namespace: hotel-app  SA: hotel-sa (IRSA)      │
                └───────────────────────┬────────────────────────┘
                                        │
                         IRSA → Secrets Manager Permissions
                                        │
                          ┌─────────────▼──────────────┐
                          │   Hotel App Pod (Docker)   │
                          │   Env from K8s Secret      │
                          └──────────────┬─────────────┘
                                         │
                                         ▼
                               RDS MySQL (Private Subnet)
```

---

## 3. AWS Components

### 3.1 VPC

The VPC module creates:

- **1 VPC**: `10.0.0.0/16`
- **2 public subnets**
- **2 private subnets**
- **1 NAT Gateway**
- **Internet Gateway**
- **Public & private route tables** with appropriate associations

### 3.2 Security Groups

- **EKS Cluster Security Group**  
  - Controls access to the EKS control plane and worker nodes.

- **RDS Security Group**  
  - Allows MySQL traffic **only** from EKS/private subnets (no public access).

### 3.3 RDS MySQL

- **Instance identifier:** `bluebird-db`  
- **Database name:** `bluebirdhotel`  
- **Connectivity:** Deployed in **private subnets**, not publicly accessible  
- **Credentials:** Stored securely in **AWS Secrets Manager**

### 3.4 ECR

Stores the hotel application Docker image:

```text
048058681474.dkr.ecr.eu-central-1.amazonaws.com/hotel:v1
```

### 3.5 EKS Cluster

- **Cluster name:** `hotel-eks`
- **Kubernetes version:** `1.29`
- **Managed Node Group:** `t3.small`
- Worker nodes run in **private subnets**
- **SSM** enabled for Session Manager access (no SSH required)

### 3.6 IRSA (IAM Roles for Service Accounts)

- A dedicated Kubernetes service account `hotel-sa` is mapped to an IAM role.
- This IAM role is granted permissions to read database credentials from **AWS Secrets Manager**.
- Pods retrieve secrets without storing persistent credentials inside the container image or Terraform code.

### 3.7 NGINX Ingress Controller

- Installed via **Helm** in the EKS cluster.
- Exposed externally through an **AWS Network Load Balancer (NLB)**.
- Provides public entry point for HTTP/HTTPS traffic to the Hotel Application.

---

## 4. Terraform Project Structure

```text
root/
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── backend.tf
├── terraform.tfvars
└── modules/
    ├── vpc/
    ├── sg/
    ├── rds/
    ├── ecr/
    └── ... (additional modules: eks, iam, etc.)
```

Each module encapsulates a specific part of the infrastructure (networking, database, container registry, compute, etc.) to keep the configuration maintainable and reusable.

---

## 5. Remote State Backend

Terraform state is stored remotely using:

- **S3 bucket:** `my-terraform-state-048058`
- **DynamoDB table:** `prod`  
  - **Partition key:** `LockID`

The backend configuration is defined inside `providers.tf` to:

- Enable team collaboration
- Ensure state locking (via DynamoDB) during `terraform apply`
- Prevent state corruption from concurrent runs

---

## 6. Handling Sensitive Data

- **Database username and password** are stored in **AWS Secrets Manager**.
- EKS pods:
  - Assume permissions via **IRSA** to access Secrets Manager.
  - Load database credentials into environment variables (via Kubernetes Secret).
- A **Kubernetes Secret** inside the `hotel-app` namespace holds DB connection configuration used by the application pods.

No raw credentials are hardcoded into Terraform files or Docker images.

---

## 7. Deployment Workflow

From the project root:

```bash
# Initialize Terraform & backend
terraform init

# Validate configuration
terraform validate

# Review the execution plan
terraform plan

# Apply changes (provision all resources)
terraform apply
```

---

## 8. Post-Deployment (Kubernetes) Steps

After the initial `terraform apply` completes:

1. **Update local kubeconfig** to point to the EKS cluster:

   ```bash
   aws eks update-kubeconfig --region eu-central-1 --name hotel-eks
   ```

2. **Create the application namespace** (if not already managed by Terraform):

   ```bash
   kubectl create namespace hotel-app
   ```

3. **Re-run Terraform** to allow Kubernetes resources that depend on the namespace (ServiceAccount, Secrets, etc.) to be created:

   ```bash
   terraform apply
   ```

4. **Retrieve the NGINX Ingress NLB hostname**:

   ```bash
   kubectl get svc ingress-nginx-controller -n ingress-nginx      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   echo
   ```

5. **Open the printed DNS hostname in a browser** to access the Hotel Application.

---

## 9. Destroying the Infrastructure

To tear down all provisioned resources:

```bash
terraform destroy
```

> ⚠️ This will remove the VPC, EKS cluster, RDS instance, NLB, and all related infrastructure.  
> Make sure you have backups of any important data before running this command.
