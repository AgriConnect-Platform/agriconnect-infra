# AgriConnect — Complete Terraform Understanding Guide

> Everything from zero to the exact way this project's infrastructure is built.
> Every concept explained, every file mapped, every alternative discussed.

---

## Table of Contents

1. [What is Terraform?](#1-what-is-terraform)
2. [How Terraform Works — The Core Lifecycle](#2-how-terraform-works--the-core-lifecycle)
3. [Project File Structure](#3-project-file-structure)
4. [State — The Brain of Terraform](#4-state--the-brain-of-terraform)
5. [Remote State + Locking in This Project](#5-remote-state--locking-in-this-project)
6. [Providers — versions.tf and providers.tf](#6-providers--versionstf-and-providerstf)
7. [Variables — variables.tf and terraform.tfvars](#7-variables--variablestf-and-terraformtfvars)
8. [Locals — locals.tf](#8-locals--localstf)
9. [Modules — How and Why](#9-modules--how-and-why)
10. [Module: networking](#10-module-networking)
11. [Module: security](#11-module-security)
12. [Module: rds](#12-module-rds)
13. [Module: s3](#13-module-s3)
14. [Module: eks](#14-module-eks)
15. [Module: cloudfront](#15-module-cloudfront)
16. [Root main.tf — Wiring Everything Together](#16-root-maintf--wiring-everything-together)
17. [cloudwatch.tf](#17-cloudwatchtf)
18. [outputs.tf](#18-outputstf)
19. [Data Sources](#19-data-sources)
20. [IRSA — IAM Roles for Service Accounts (Deep Dive)](#20-irsa--iam-roles-for-service-accounts-deep-dive)
21. [Secrets Manager vs Hardcoding](#21-secrets-manager-vs-hardcoding)
22. [Terraform Workspaces](#22-terraform-workspaces)
23. [Bootstrap — The Chicken and Egg Problem](#23-bootstrap--the-chicken-and-egg-problem)
24. [CI/CD Integration — infra-terraform.yml](#24-cicd-integration--infra-terraformyml)
25. [Resource Dependencies and depends_on](#25-resource-dependencies-and-depends_on)
26. [for_each and count — Dynamic Resources](#26-for_each-and-count--dynamic-resources)
27. [Sensitive Outputs and Variables](#27-sensitive-outputs-and-variables)
28. [Tagging Strategy](#28-tagging-strategy)
29. [Advanced Concepts Used in This Project](#29-advanced-concepts-used-in-this-project)
30. [What Could Have Been Done Differently](#30-what-could-have-been-done-differently)

---

## 1. What is Terraform?

Terraform is an **Infrastructure as Code (IaC)** tool made by HashiCorp. Instead of clicking through the AWS Console to create resources, you write code that describes what you want — Terraform figures out how to create, update, or delete resources to match that description.

**Why it matters:**
- Infrastructure is version-controlled in Git (auditable, reviewable, rollbackable)
- Same code creates identical environments (dev, prod)
- Destroy and recreate the entire infrastructure with one command
- Changes go through CI/CD pipelines with approval gates

**How it differs from other tools:**

| Tool | Approach | Language |
|---|---|---|
| Terraform | Declarative — describe desired state | HCL |
| Ansible | Imperative — describe steps to run | YAML |
| CloudFormation | Declarative — AWS only | YAML/JSON |
| Pulumi | Declarative — real programming languages | Python/TS/Go |

In this project, **Terraform** was chosen because it is cloud-agnostic (could move to Azure/GCP later), has the largest module ecosystem, and is the industry standard for EKS deployments.

---

## 2. How Terraform Works — The Core Lifecycle

```
Write .tf files → terraform init → terraform plan → terraform apply → infrastructure exists
                                                                            ↓
                                                              terraform state tracks it
```

### terraform init
Downloads provider plugins (AWS, archive), initialises the remote state backend, downloads any referenced modules.

```bash
terraform init
```

Run this whenever you add a new provider or module, or when someone clones the repo fresh.

### terraform plan
Compares your `.tf` files against the current **state file**. Shows exactly what will be created, changed, or destroyed — without touching anything.

```bash
terraform plan -var-file=terraform.tfvars -out=tfplan
```

The `-out=tfplan` saves the plan so `apply` uses the exact same plan (important in CI — plan and apply must match).

### terraform apply
Executes the plan. Calls AWS APIs to create/modify/delete resources.

```bash
terraform apply tfplan
```

### terraform destroy
Destroys everything tracked in state. Useful for spinning down dev environments to save cost.

```bash
terraform destroy -var-file=terraform.tfvars
```

### terraform fmt
Formats all `.tf` files to canonical HCL style. The CI pipeline runs `terraform fmt -check` to fail if code is unformatted.

### terraform validate
Checks HCL syntax and internal consistency — catches typos, missing required fields, wrong types. Does not call AWS APIs.

---

## 3. Project File Structure

```
stage-infra/
├── terraform/
│   ├── versions.tf          # Terraform version + backend + required providers
│   ├── providers.tf         # AWS provider config (multi-region for CloudFront)
│   ├── main.tf              # Root module — all resources + module calls
│   ├── variables.tf         # Input variable declarations
│   ├── locals.tf            # Computed local values
│   ├── outputs.tf           # Values exposed after apply
│   ├── cloudwatch.tf        # CloudWatch log groups
│   ├── terraform.tfvars     # Actual variable values (committed — no secrets here)
│   ├── .gitignore           # Excludes *.tfstate, crash.log, override files
│   └── modules/
│       ├── networking/      # VPC, subnets, IGW, NAT, route tables
│       ├── security/        # Security groups, Lambda IAM role, EventBridge role
│       ├── rds/             # RDS MySQL instance + subnet group
│       ├── s3/              # S3 produce-images bucket
│       ├── eks/             # EKS cluster, node group, IRSA, ECR repos
│       └── cloudfront/      # WAF, CloudFront distribution
├── bootstrap/
│   └── main.tf              # Creates S3 bucket + DynamoDB for state (run once)
├── lambda/                  # Lambda function source code (zipped by Terraform)
│   ├── weather-alert-processor/
│   ├── farmbot/
│   └── buyerbot/
└── .github/
    └── workflows/
        ├── infra-terraform.yml   # CI/CD pipeline for terraform
        └── bootstrap.yml         # One-time bootstrap runner
```

### Why this structure?

The **root module** (`terraform/`) is the entry point. It calls child modules and creates resources that span multiple modules (like connecting EKS to RDS via security groups). Each module owns a specific concern and knows nothing about other modules — it only receives inputs and exposes outputs.

---

## 4. State — The Brain of Terraform

The **state file** (`terraform.tfstate`) is a JSON file that maps your HCL code to real AWS resources. It contains the actual resource IDs, ARNs, IP addresses — everything Terraform needs to know what already exists.

```json
{
  "resources": [
    {
      "type": "aws_vpc",
      "name": "main",
      "instances": [
        {
          "attributes": {
            "id": "vpc-0abc123",
            "cidr_block": "10.0.0.0/16"
          }
        }
      ]
    }
  ]
}
```

**Why state matters:**
- Without state, Terraform wouldn't know that `vpc-0abc123` corresponds to your `aws_vpc.main` resource
- Plan compares `.tf` files → state → actual AWS → shows diff
- Deleting a resource from `.tf` tells Terraform to destroy the real AWS resource

**What state is NOT:**
- Not a backup of your infrastructure
- Not always in sync with reality (someone manually deleted a resource → state drift)
- Not something you edit by hand

---

## 5. Remote State + Locking in This Project

### The Problem With Local State

If state lives on your laptop, no one else can safely run Terraform at the same time. Two people running `terraform apply` simultaneously can corrupt the state file.

### How This Project Solves It

**File: `terraform/versions.tf`**
```hcl
terraform {
  backend "s3" {
    bucket       = "agriconnect-tfstate-893431614084"
    key          = "agriconnect/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

**Breaking this down line by line:**

| Line | What it does |
|---|---|
| `bucket` | The S3 bucket where the state file lives |
| `key` | The path inside the bucket — like a folder/filename |
| `region` | Which AWS region the S3 bucket is in |
| `use_lockfile = true` | Enables S3 native state locking (Terraform 1.10+) |
| `encrypt = true` | State file is encrypted at rest using AWS SSE |

### State Locking Explained

When `terraform apply` starts, Terraform writes a `.tflock` file to the same S3 bucket. If another run tries to start, it sees the lock and fails immediately with:

```
Error acquiring the state lock
```

When apply finishes (success or failure), the `.tflock` is deleted. This prevents two CI runs from corrupting each other's state.

### Before Terraform 1.10 — DynamoDB Locking

Previously, locking required a separate DynamoDB table:
```hcl
# OLD approach (deprecated in Terraform 1.10+)
backend "s3" {
  bucket         = "agriconnect-tfstate-893431614084"
  key            = "agriconnect/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "agriconnect-terraform-locks"  # ← separate AWS resource needed
  encrypt        = true
}
```

The DynamoDB table had a `LockID` (String) hash key. Each lock was a PutItem call; unlock was DeleteItem. This project initially used this approach, then migrated to `use_lockfile` because:
- No extra DynamoDB resource to manage
- No DynamoDB costs
- Native to S3 backend — simpler setup

### Where the State File Lives

```
S3 bucket: agriconnect-tfstate-893431614084
  └── agriconnect/terraform.tfstate    ← your entire infrastructure described here
```

The account ID is in the bucket name to make it globally unique (S3 bucket names are global across all AWS accounts).

---

## 6. Providers — versions.tf and providers.tf

### What is a Provider?

A provider is a plugin that knows how to talk to a specific cloud or service. The AWS provider translates Terraform HCL into AWS API calls.

**File: `terraform/versions.tf`**
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
```

**Version constraints:**

| Constraint | Meaning |
|---|---|
| `~> 5.0` | Any 5.x version, but not 6.0 (compatible updates only) |
| `>= 1.6.0` | Any version at or above 1.6.0 |
| `= 5.3.0` | Exact version only |
| `>= 5.0, < 6.0` | Range |

**The archive provider** is used to zip Lambda function source code into deployment packages:
```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/weather-alert-processor/index.js"
  output_path = "${path.module}/lambda_package.zip"
}
```

### Multi-Region Providers

**File: `terraform/providers.tf`**

CloudFront WAF (Web ACL) must be created in `us-east-1` — AWS requirement. But all other resources are in `ap-south-1`. Solution: two provider aliases.

```hcl
provider "aws" {
  region = var.aws_region  # ap-south-1
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"     # for WAF only
}
```

The CloudFront module receives both:
```hcl
module "cloudfront" {
  providers = {
    aws           = aws             # default (ap-south-1)
    aws.us_east_1 = aws.us_east_1  # aliased (us-east-1) for WAF
  }
}
```

Inside the cloudfront module, WAF is created with the `aws.us_east_1` provider.

---

## 7. Variables — variables.tf and terraform.tfvars

### What are Variables?

Variables are inputs to your Terraform code. They let you reuse the same code with different values — same module, different bucket name, different instance type.

### Declaring Variables — variables.tf

```hcl
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true   # never printed in plan output or logs
}

variable "availability_zones" {
  description = "List of AZs to use"
  type        = list(string)
}
```

**Variable types in Terraform:**

| Type | Example |
|---|---|
| `string` | `"ap-south-1"` |
| `number` | `2` |
| `bool` | `true` |
| `list(string)` | `["ap-south-1a", "ap-south-1b"]` |
| `map(string)` | `{key = "value"}` |
| `object({...})` | Complex nested type |

### Providing Values — terraform.tfvars

```hcl
aws_region             = "ap-south-1"
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones     = ["ap-south-1a", "ap-south-1b"]
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
eks_node_min_size      = 2
eks_node_max_size      = 4
```

**Sensitive variables — NOT in tfvars:**
```hcl
# terraform.tfvars has this comment:
# rds_password → set via TF_VAR_rds_password (GitHub Secret)
```

Terraform reads environment variables prefixed with `TF_VAR_`:
```bash
export TF_VAR_rds_password="mysecretpassword"
terraform apply   # picks up rds_password automatically
```

In the CI pipeline (`infra-terraform.yml`):
```yaml
env:
  TF_VAR_rds_password: ${{ secrets.TF_VAR_RDS_PASSWORD }}
  TF_VAR_jwt_secret:   ${{ secrets.TF_VAR_JWT_SECRET }}
  TF_VAR_smtp_pass:    ${{ secrets.TF_VAR_SMTP_PASS }}
```

### Variable Precedence (highest to lowest)

1. Command line: `-var="key=value"`
2. `.auto.tfvars` files
3. `terraform.tfvars`
4. Environment variables (`TF_VAR_*`)
5. Default in `variable` block

---

## 8. Locals — locals.tf

### What are Locals?

Locals are computed values — like variables but derived from other values. They avoid repeating the same expression multiple times.

**File: `terraform/locals.tf`**

```hcl
locals {
  # Detect which workspace is active
  workspace_env = terraform.workspace == "default" ? "dev" : terraform.workspace

  # Per-environment configuration
  config = {
    dev = {
      rds_instance_class   = "db.t3.micro"
      rds_allocated_storage = 20
    }
    prod = {
      rds_instance_class   = "db.t3.small"
      rds_allocated_storage = 50
    }
  }[local.workspace_env]

  # AWS account info
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  name_prefix = "agriconnect-${local.workspace_env}"

  # Tags applied to every resource
  common_tags = {
    Environment = local.workspace_env
    Project     = "AgriConnect"
    ManagedBy   = "Terraform"
    Owner       = "Asad"
  }
}
```

**Key patterns:**

### Ternary Expression
```hcl
workspace_env = terraform.workspace == "default" ? "dev" : terraform.workspace
```
Reads: "if workspace is 'default', use 'dev', otherwise use the workspace name."

### Map Lookup
```hcl
config = {
  dev  = { rds_instance_class = "db.t3.micro" }
  prod = { rds_instance_class = "db.t3.small" }
}[local.workspace_env]
```
Selects the right config object based on the current environment. `local.config.rds_instance_class` gives you `"db.t3.micro"` in dev.

### String Interpolation
```hcl
name_prefix = "agriconnect-${local.workspace_env}"
# → "agriconnect-dev" or "agriconnect-prod"
```

### Using Locals in Resources
```hcl
resource "aws_eks_cluster" "main" {
  name = "${local.name_prefix}-eks"    # → "agriconnect-dev-eks"
  tags = local.common_tags             # every resource gets these tags
}
```

---

## 9. Modules — How and Why

### What is a Module?

A module is a directory of `.tf` files that can be called like a function. It takes inputs (variables), creates resources, and exposes outputs. The caller doesn't need to know the internals.

### Module Structure

Every module has this pattern:
```
modules/eks/
├── main.tf       # resources
├── variables.tf  # inputs
└── outputs.tf    # what the module exposes to the caller
```

### Calling a Module

In root `main.tf`:
```hcl
module "eks" {
  source = "./modules/eks"               # path to module directory

  # These match variable declarations in modules/eks/variables.tf
  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id   # output from networking module
  private_subnet_ids = module.networking.private_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_desired_size  = var.eks_node_desired_size
}
```

### Module Outputs

After a module runs, it exposes outputs. The root module reads them:
```hcl
# Using eks module output in root main.tf
resource "aws_ssm_parameter" "cluster_name" {
  value = module.eks.cluster_name  # ← comes from modules/eks/outputs.tf
}
```

### Why Modules?

| Without modules | With modules |
|---|---|
| One 2000-line main.tf | Focused files, each under 200 lines |
| Hard to reuse networking in another project | `source = "git::https://github.com/..."` |
| Hard to test one part in isolation | Deploy just the networking module |
| All team members edit the same file | Ownership by team/concern |

### Module Dependency Graph in This Project

```
root (main.tf)
├── module.networking      ← no dependencies
├── module.security        ← needs: module.networking.vpc_id
├── module.rds             ← needs: module.networking.private_subnet_ids
│                                   module.security.common_sg_id
├── module.s3              ← no dependencies
├── module.eks             ← needs: module.networking.vpc_id
│                                   module.networking.public_subnet_ids
│                                   module.networking.private_subnet_ids
│                                   module.security.common_sg_id
└── module.cloudfront      ← needs: var.eks_alb_dns_name (from tfvars)
                                    aws_s3_bucket.frontend (root resource)
```

Terraform automatically resolves this graph and creates resources in the right order.

---

## 10. Module: networking

**File: `terraform/modules/networking/main.tf`**

This module creates the entire VPC layer.

### VPC
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr    # 10.0.0.0/16 — 65,536 IPs
  enable_dns_hostnames = true            # pods resolve DNS names
  enable_dns_support   = true
  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}
```

**What is a VPC?** A Virtual Private Cloud — your isolated network in AWS. Everything lives inside it. Nothing can communicate with it unless you explicitly allow it.

### Internet Gateway
```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```
Allows traffic between public subnets and the internet. Without this, nothing in the VPC can reach the internet or be reached from it.

### Public Subnets (2)
```hcl
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true   # instances get public IPs automatically
}
```
CIDRs: `10.0.1.0/24` (ap-south-1a), `10.0.2.0/24` (ap-south-1b)
ALB lives here. NAT Gateway lives here.

### Private Subnets (2)
```hcl
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  # no map_public_ip_on_launch — stays private
}
```
CIDRs: `10.0.10.0/24` (ap-south-1a), `10.0.11.0/24` (ap-south-1b)
EKS nodes live here. RDS lives here. Nothing here is directly reachable from the internet.

### NAT Gateway
```hcl
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # must be in a PUBLIC subnet
}
```

**What is NAT?** Network Address Translation. Private subnet instances need to talk to the internet (to pull Docker images, call AWS APIs). They can't have public IPs. NAT Gateway sits in the public subnet and translates: private IP → NAT's public IP → internet. Responses come back the same way.

**Cost note:** NAT Gateway costs ~$33/month + $0.045/GB data. The `cost_estimation` Terraform output flags this.

### Route Tables
```hcl
# Public route table — sends internet traffic via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Private route table — sends internet traffic via NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

### Module Outputs
```hcl
output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"   { value = aws_subnet.public[*].id }
output "private_subnet_ids"  { value = aws_subnet.private[*].id }
```

These outputs are consumed by every other module that needs to know where to place resources.

---

## 11. Module: security

**File: `terraform/modules/security/main.tf`**

### Common Security Group
```hcl
resource "aws_security_group" "common" {
  name   = "${var.name_prefix}-common-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # HTTP from anywhere
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # HTTPS from anywhere
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # MySQL only from within VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"             # all outbound allowed
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Security group = stateful firewall.** If you allow an inbound connection, the response is automatically allowed back. This is unlike NACLs (Network Access Control Lists) which are stateless.

### Lambda IAM Role
```hcl
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}
```

**What is `assume_role_policy`?** This is the trust policy — it defines WHO can use this role. Here, only the Lambda service can assume it. Without this, even if you attach permissions to the role, no one can use it.

---

## 12. Module: rds

**File: `terraform/modules/rds/main.tf`**

### DB Subnet Group
```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids   # always in private subnets
}
```

RDS must know which subnets it can use. By specifying only private subnets, the database is never accessible from the internet.

### RDS Instance
```hcl
resource "aws_db_instance" "main" {
  identifier        = "${var.name_prefix}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.rds_instance_class      # db.t3.micro (from locals)
  allocated_storage = var.allocated_storage        # 20 GB in dev

  db_name  = var.db_name      # "agriconnect"
  username = var.db_username  # "admin"
  password = var.db_password  # from TF_VAR_rds_password secret

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.common_sg_id]

  publicly_accessible = false   # critical — never expose DB to internet
  skip_final_snapshot = true    # dev only — prod should be false
  multi_az            = false   # dev only — prod should be true
}
```

**What could have been done differently:**
- `multi_az = true` for production (standby replica in another AZ for failover)
- `skip_final_snapshot = false` for production (snapshot before destroy)
- Read replica for read-heavy workloads
- Aurora Serverless v2 — auto-scales, cheaper at low usage

---

## 13. Module: s3

**File: `terraform/modules/s3/main.tf`**

```hcl
resource "aws_s3_bucket" "produce_images" {
  bucket = var.produce_images_bucket   # agriconnect-produce-images-893431614084
}

resource "aws_s3_bucket_cors_configuration" "produce_images" {
  bucket = aws_s3_bucket.produce_images.id
  cors_rule {
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]    # could be restricted to CloudFront domain
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}
```

CORS allows the React frontend to upload images directly to S3 from the browser (presigned URLs) without routing the file through your servers.

**What could have been done differently:**
- Restrict CORS to only your CloudFront domain
- Add lifecycle rules to move old images to S3 Glacier after 90 days (cost savings)
- Enable S3 Object Lock for compliance

---

## 14. Module: eks

**File: `terraform/modules/eks/main.tf`** — the largest module (363 lines)

### Cluster IAM Role
```hcl
resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
```

The EKS control plane needs this role to manage the cluster (call EC2 APIs, create ENIs, etc.).

### Node Group IAM Role
```hcl
resource "aws_iam_role" "nodes" {
  name = "${var.name_prefix}-eks-node-role"
  assume_role_policy = jsonencode({
    Statement = [{
      Principal = { Service = "ec2.amazonaws.com" }   # EC2, not EKS
    }]
  })
}

# Attach 4 managed policies
resource "aws_iam_role_policy_attachment" "worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

**Why 4 policies?**
- `AmazonEKSWorkerNodePolicy` — node can register with the cluster
- `AmazonEKS_CNI_Policy` — VPC CNI plugin can manage ENIs (pod networking)
- `AmazonEC2ContainerRegistryReadOnly` — nodes can pull images from ECR
- `CloudWatchAgentServerPolicy` — nodes can send metrics/logs to CloudWatch

### EKS Cluster
```hcl
resource "aws_eks_cluster" "main" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
```

**Control plane logs:** Audit logs record every API call to your cluster (who did what, when). Essential for security and debugging.

### Node Group
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids   # nodes in PRIVATE subnets only

  instance_types = [var.node_instance_type]   # ["t3.medium"]

  scaling_config {
    desired_size = var.node_desired_size   # 2
    min_size     = var.node_min_size       # 2
    max_size     = var.node_max_size       # 4
  }
}
```

### ECR Repositories
```hcl
resource "aws_ecr_repository" "services" {
  for_each = toset(["auth", "marketplace", "order", "media", "notification"])

  name                 = "agriconnect-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true   # ECR also scans images on push (in addition to Trivy in CI)
  }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

**`for_each` pattern:** Creates 5 resources (one per service name) instead of copy-pasting the same block 5 times. `each.key` = `"auth"`, `each.value` = the resource object.

### OIDC Provider (Gateway for IRSA)
```hcl
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}
```

This creates the bridge between EKS's Kubernetes identity system and AWS IAM. Without this, pods cannot assume IAM roles.

---

## 15. Module: cloudfront

**File: `terraform/modules/cloudfront/main.tf`** (274 lines)

### WAF Web ACL (us-east-1 provider)
```hcl
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1   # CloudFront WAF must be in us-east-1
  name     = "${var.name_prefix}-waf"
  scope    = "CLOUDFRONT"

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    # Blocks SQLi, XSS, and other OWASP Top 10
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
  }

  rule {
    name     = "LoginRateLimit"
    priority = 3
    # 100 requests per 5 minutes per IP to /api/auth/login
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }
  }
}
```

### CloudFront Distribution
```hcl
resource "aws_cloudfront_distribution" "main" {
  # Origin 1: S3 (frontend React app)
  origin {
    domain_name = var.s3_website_endpoint
    origin_id   = "S3-Frontend"
    custom_origin_config {
      http_port              = 80
      origin_protocol_policy = "http-only"
    }
  }

  # Origin 2: ALB (API backend)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-Backend"
    custom_origin_config {
      http_port              = 80
      origin_protocol_policy = "http-only"
    }
    custom_header {
      name  = "X-Forwarded-By"
      value = "CloudFront"
    }
  }

  # /api/* → ALB (no caching)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "ALB-Backend"
    forwarded_values {
      query_string = true
      cookies      { forward = "all" }
      headers      = ["*"]
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  # /assets/* → S3 (aggressive cache — 1 year)
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    default_ttl            = 31536000   # 1 year
    max_ttl                = 31536000
    compress               = true       # gzip/brotli
  }

  # Default → S3 (React SPA routing)
  default_cache_behavior {
    target_origin_id       = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
  }

  # SPA fallback — 404 and 403 → index.html
  custom_error_response {
    error_code         = 404
    response_page_path = "/index.html"
    response_code      = 200
  }

  web_acl_id = aws_wafv2_web_acl.main.arn
}
```

**Why SPA error handling?** React Router handles routing client-side. When a user goes to `/dashboard`, CloudFront/S3 doesn't have a file named `dashboard`. Without the 404→index.html rule, users get a white error page instead of the React app loading.

---

## 16. Root main.tf — Wiring Everything Together

The root `main.tf` (642 lines) is where all the pieces connect. Beyond calling modules, it creates:

### Secrets Manager
```hcl
resource "aws_secretsmanager_secret" "database" {
  name                    = "agriconnect/${local.workspace_env}/database"
  recovery_window_in_days = 0   # instant delete (dev) — set to 30 for prod
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    host     = module.rds.endpoint
    port     = 3306
    database = var.rds_db_name
    username = var.rds_username
    password = var.rds_password
  })
}
```

Pods don't get the DB password as an env variable. They call Secrets Manager at startup using their IRSA role to fetch it. This means rotating the password doesn't require redeploying pods.

### SNS Topics
```hcl
resource "aws_sns_topic" "events" {
  name = "AgriConnect-Events"
}

resource "aws_sns_topic" "monitoring_alerts" {
  name = "AgriConnect-MonitoringAlerts"
}
```

### SQS Queue + Dead Letter Queue
```hcl
resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "AgriConnect-Notifications-DLQ"
  message_retention_seconds = 1209600   # 14 days
}

resource "aws_sqs_queue" "notifications" {
  name                       = "AgriConnect-Notifications-Queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400   # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 3   # after 3 failed attempts, move to DLQ
  })
}
```

**What is a DLQ?** If the notification service fails to process a message 3 times, the message goes to the Dead Letter Queue instead of being lost. You can inspect DLQ messages to debug why processing failed.

### SQS Policy (allowing SNS to send)
```hcl
resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.url
  policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notifications.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn }
      }
    }]
  })
}
```

This is an **SNS→SQS subscription policy**. It says "only the AgriConnect-Events SNS topic can send messages to this queue." The Condition prevents other SNS topics from writing to your queue.

### Lambda Functions
```hcl
resource "aws_lambda_function" "weather_alert" {
  filename         = data.archive_file.lambda.output_path   # zipped by Terraform
  function_name    = "weather-alert-processor"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  role             = module.security.lambda_role_arn
  source_code_hash = data.archive_file.lambda.output_base64sha256
  # ↑ Triggers redeployment only when source code actually changes
}
```

**`source_code_hash`:** Terraform hashes the zip file. If the hash doesn't change (code unchanged), Terraform skips the Lambda update. This prevents unnecessary Lambda redeployments on every apply.

### API Gateway (HTTP API)
```hcl
resource "aws_apigatewayv2_api" "farmbot" {
  name          = "farmbot-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "farmbot" {
  api_id             = aws_apigatewayv2_api.farmbot.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.farmbot_chatbot.invoke_arn
}

resource "aws_apigatewayv2_route" "farmbot" {
  api_id    = aws_apigatewayv2_api.farmbot.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.farmbot.id}"
}
```

HTTP API Gateway is cheaper and faster than REST API Gateway. `AWS_PROXY` integration passes the full HTTP request to Lambda as a JSON event.

### EventBridge Scheduler
```hcl
resource "aws_scheduler_schedule" "weather_check" {
  name                         = "weather-alert-check"
  schedule_expression          = var.weather_schedule_expression   # "rate(6 hours)"
  schedule_expression_timezone = "Asia/Kolkata"

  flexible_time_window { mode = "OFF" }

  target {
    arn      = aws_lambda_function.weather_alert.arn
    role_arn = module.security.scheduler_role_arn
    input    = jsonencode({ source = "scheduler" })
  }
}
```

**EventBridge Scheduler vs CloudWatch Events:** EventBridge Scheduler is newer, supports timezone-aware scheduling, and has a dedicated `aws_scheduler_schedule` resource. CloudWatch Events (`aws_cloudwatch_event_rule`) is the older equivalent — still works but Scheduler is preferred for new implementations.

### SSM Parameter Store
```hcl
resource "aws_ssm_parameter" "farmbot_api_url" {
  name  = "/agriconnect/farmbot_api_url"
  type  = "String"
  value = "${trimsuffix(aws_apigatewayv2_stage.farmbot.invoke_url, "/")}/chat"
}
```

After Terraform runs, the API Gateway URL is stored in SSM. The CI/CD pipeline (`cd-frontend.yml`) reads this parameter when building the React frontend, so the frontend knows the correct API URLs without hardcoding them.

**The full flow:**
```
terraform apply → creates API Gateway → URL stored in SSM
           ↓
cd-frontend.yml → aws ssm get-parameter /agriconnect/farmbot_api_url
           ↓
npm run build (VITE_FARMBOT_API_URL=<ssm value>)
           ↓
React app has correct URL baked in at build time
```

---

## 17. cloudwatch.tf

```hcl
resource "aws_cloudwatch_log_group" "eks_application" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/application"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "lambda_weather" {
  name              = "/aws/lambda/weather-alert-processor"
  retention_in_days = 30
}
```

**Why define log groups in Terraform?** AWS creates log groups automatically when Lambda runs, but with no retention policy — logs accumulate forever and cost money. By pre-creating them with `retention_in_days = 30`, logs older than 30 days are auto-deleted.

### CloudWatch Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2          # must breach for 2 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300        # 5-minute intervals
  statistic           = "Average"
  threshold           = 80         # alert if CPU > 80%
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
}
```

All 5 alarms publish to `AgriConnect-MonitoringAlerts` SNS topic which sends an email to `admin_email`.

---

## 18. outputs.tf

Outputs serve two purposes:
1. Show useful values after `terraform apply`
2. Allow other Terraform configurations to reference these values (via `terraform_remote_state` data source)

```hcl
output "eks_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
```

After apply, you can immediately run the output value to configure kubectl.

```hcl
output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true   # not shown in plan/apply output, not in CI logs
}
```

```hcl
output "cost_estimation" {
  description = "Approximate monthly cost breakdown for deployed resources (ap-south-1, USD)"
  value = {
    eks_nodes         = "${var.eks_node_desired_size}x ${var.eks_node_instance_type} nodes = ~$${var.eks_node_desired_size * 15}/mo"
    eks_control_plane = "EKS cluster fee = ~$72/mo"
    rds               = "db.t3.micro 20 GB PostgreSQL = ~$15/mo"
    nat_gateway       = "1x NAT Gateway + data transfer = ~$33+/mo"
    alb               = "1x Application Load Balancer = ~$18/mo"
    total_estimate    = "~$160-175/month (EKS nodes + NAT Gateway = ~70% of cost)"
    optimization_tip  = "Add VPC endpoints for S3 and SQS to cut NAT Gateway data charges"
  }
}
```

**How outputs are read in CI:**
```bash
terraform output -raw eks_cluster_name       # → "agriconnect-dev-eks"
terraform output -json cost_estimation       # → JSON object
```

---

## 19. Data Sources

Data sources read existing AWS resources — they don't create anything.

```hcl
# Current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Used in locals:
account_id = data.aws_caller_identity.current.account_id   # → "893431614084"
region     = data.aws_region.current.name                  # → "ap-south-1"
```

```hcl
# EKS OIDC certificate thumbprint (needed to create OIDC provider)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

```hcl
# Zip Lambda source code into a deployment package
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/weather-alert-processor/index.js"
  output_path = "${path.module}/lambda_package.zip"
}
```

**Data source vs Resource:**

| | Resource | Data Source |
|---|---|---|
| Keyword | `resource` | `data` |
| Action | Creates/modifies/destroys | Read-only |
| In state? | Yes | No (re-fetched every plan) |
| Example | `aws_vpc.main` | `aws_caller_identity.current` |

---

## 20. IRSA — IAM Roles for Service Accounts (Deep Dive)

IRSA is the most important security concept in this project.

### The Problem It Solves

Without IRSA, pods need AWS credentials to call services like S3, SQS, Secrets Manager. You'd have to:
- Hardcode access keys (terrible — rotations, leaks)
- Put them in environment variables (visible in pod spec, K8s Secrets)
- Use the node's IAM role (all pods on the node share permissions — too broad)

### How IRSA Works

```
Pod starts
  ↓
EKS injects environment variables into the pod:
  AWS_ROLE_ARN = arn:aws:iam::893431614084:role/agriconnect-dev-eks-services-role
  AWS_WEB_IDENTITY_TOKEN_FILE = /var/run/secrets/eks.amazonaws.com/serviceaccount/token
  ↓
AWS SDK (in Node.js) automatically detects these env vars
  ↓
SDK calls STS: "I have this JWT token, I want to assume this role"
  ↓
STS validates: JWT is signed by EKS OIDC → matches the OIDC provider → allow
  ↓
STS returns temporary credentials (expire in 1 hour, auto-renewed)
  ↓
SDK uses those credentials to call S3 / SQS / Secrets Manager
```

### Terraform Implementation

**Step 1: OIDC Provider**
```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}
```

This registers your EKS cluster's identity provider with AWS IAM. AWS now trusts JWTs signed by this cluster.

**Step 2: IAM Role with Trust Policy**
```hcl
resource "aws_iam_role" "services_irsa" {
  name = "${var.name_prefix}-eks-services-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" =
            "system:serviceaccount:production:agriconnect"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" =
            "sts.amazonaws.com"
        }
      }
    }]
  })
}
```

**The Condition is critical.** It locks the role to:
- Namespace: `production`
- ServiceAccount name: `agriconnect`

No other pod, even on the same cluster, can assume this role.

**Step 3: Permissions**
```hcl
resource "aws_iam_role_policy" "services_irsa" {
  role = aws_iam_role.services_irsa.id
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = "arn:aws:secretsmanager:*:*:secret:agriconnect/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::agriconnect-*/*"
      }
    ]
  })
}
```

**Step 4: Helm ServiceAccount Annotation**
In `stage-helm/helm/agriconnect/templates/serviceaccount.yaml`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: agriconnect
  namespace: {{ .Values.global.namespace }}
  annotations:
    eks.amazonaws.com/role-arn: {{ .Values.global.irsaRoleArn | quote }}
```

This annotation tells EKS: "Pods using this ServiceAccount should get the IRSA credentials for that role ARN."

**Step 5: Role ARN stored in Terraform output → read by Helm**
```hcl
# outputs.tf
output "eks_services_irsa_role_arn" {
  value = module.eks.services_irsa_role_arn
}
```

The bootstrap script reads this output and sets it in `values.yaml` before deploying Helm.

---

## 21. Secrets Manager vs Hardcoding

### How Secrets Flow in This Project

```
Terraform runs:
  → creates RDS instance (password from TF_VAR_rds_password)
  → stores password in Secrets Manager at "agriconnect/dev/database"

Pod starts:
  → gets IRSA credentials automatically
  → calls Secrets Manager.GetSecretValue("agriconnect/dev/database")
  → parses JSON: { host, port, database, username, password }
  → connects to MySQL

Password rotation:
  → update secret in Secrets Manager
  → pods pick up new password on next connection pool restart
  → no redeployment needed
```

### What NOT to Do
```yaml
# NEVER DO THIS in Kubernetes
env:
  - name: DB_PASSWORD
    value: "mysecretpassword"   # visible in kubectl describe pod
```

```yaml
# ALSO AVOID (base64 is not encryption)
kind: Secret
data:
  password: bXlzZWNyZXRwYXNzd29yZA==   # easily decoded
```

Secrets Manager encrypts at rest with KMS, has audit logging (CloudTrail), and supports rotation.

---

## 22. Terraform Workspaces

```hcl
# locals.tf
workspace_env = terraform.workspace == "default" ? "dev" : terraform.workspace
```

**What is a workspace?** A named instance of your state. The default workspace is named `"default"`.

```bash
terraform workspace new prod    # create prod workspace
terraform workspace select prod # switch to it
terraform apply                 # now creates "agriconnect-prod-*" resources
```

This project maps:
- `default` workspace → `dev` environment
- `prod` workspace → `prod` environment

The `locals.config` map selects different RDS instance sizes per environment:
- dev: `db.t3.micro`, 20 GB
- prod: `db.t3.small`, 50 GB

**Alternative approach:** Separate `environments/dev/` and `environments/prod/` directories each with their own `terraform.tfvars`. Avoids workspace complexity but duplicates some configuration.

---

## 23. Bootstrap — The Chicken and Egg Problem

**The problem:** Terraform needs an S3 bucket for remote state. But to create that S3 bucket with Terraform, you need state somewhere. Circular.

**Solution: `bootstrap/main.tf`**

```hcl
# This runs ONCE, manually, before anything else
# It has NO remote backend — uses local state

resource "aws_s3_bucket" "tfstate" {
  bucket = "agriconnect-tfstate-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "tflock" {
  name         = "agriconnect-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**Run once:**
```bash
cd terraform/bootstrap
terraform init    # local state
terraform apply   # creates S3 bucket
# → now the main terraform/ can use that bucket as its backend
```

**The bootstrap's own state** lives locally and is not committed. That's fine — you rarely change bootstrap resources.

---

## 24. CI/CD Integration — infra-terraform.yml

```yaml
jobs:
  scan:               # Trivy IaC scan — no AWS credentials needed
    runs-on: ubuntu-latest
    steps:
      - run: trivy config terraform/ --severity CRITICAL,HIGH

  plan:               # needs scan to pass
    needs: scan
    environment: (none — just needs AWS credentials)
    steps:
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform fmt -check -recursive    # fail if unformatted
      - run: terraform validate
      - run: terraform plan -out=tfplan
      - uses: actions/upload-artifact@v4        # save plan for apply job
          with:
            name: tfplan

  apply:              # needs plan + MANUAL APPROVAL via environment gate
    needs: plan
    environment: production   # ← triggers approval requirement in GitHub
    steps:
      - uses: actions/download-artifact@v4      # get the exact plan from plan job
          with:
            name: tfplan
      - run: terraform apply tfplan             # apply exactly what was planned
```

**Why upload/download the plan artifact?** The `plan` job and `apply` job run on different runners (different VMs). The plan file is not shared between them. By uploading as an artifact, the apply job downloads the exact same plan and applies it — no drift between what you approved and what gets applied.

**Why `environment: production` on apply only?** You want to see the plan freely (no cost, no risk), but need human approval before actually changing infrastructure.

---

## 25. Resource Dependencies and depends_on

Terraform usually figures out dependencies automatically through references:
```hcl
resource "aws_db_instance" "main" {
  db_subnet_group_name = aws_db_subnet_group.main.name  # ← implicit dependency
}
# Terraform knows to create aws_db_subnet_group first
```

But sometimes you need explicit dependencies:
```hcl
resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]
  # ↑ must wait for public access block to be configured first
}
```

Without `depends_on`, Terraform might try to apply the policy before the public access settings are saved, causing a race condition error.

---

## 26. for_each and count — Dynamic Resources

### count (positional)
```hcl
resource "aws_subnet" "public" {
  count     = length(var.public_subnet_cidrs)   # 2
  cidr_block = var.public_subnet_cidrs[count.index]
}
# creates: aws_subnet.public[0] and aws_subnet.public[1]
```

**Problem with count:** If you remove item 0 from the list, Terraform renumbers everything — `[1]` becomes `[0]`. This can trigger unexpected destroys.

### for_each (keyed)
```hcl
resource "aws_ecr_repository" "services" {
  for_each = toset(["auth", "marketplace", "order", "media", "notification"])
  name     = "agriconnect-${each.key}"
}
# creates: aws_ecr_repository.services["auth"], ["marketplace"], etc.
```

**for_each is safer:** Resources are keyed by name. Removing `"auth"` only destroys `services["auth"]`, not the others. Preferred over `count` for anything not purely positional.

### Dynamic Blocks
```hcl
resource "aws_security_group" "common" {
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

This project doesn't use dynamic blocks heavily, but they're useful for making security group rules configurable.

---

## 27. Sensitive Outputs and Variables

```hcl
variable "rds_password" {
  type      = string
  sensitive = true   # never shown in plan output or logs
}

output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true   # shown as (sensitive value) in terraform output
}
```

**How to read a sensitive output in CI:**
```bash
terraform output -raw rds_endpoint   # bypasses the sensitive guard for scripts
```

In the CI pipeline, the RDS endpoint is read this way and set as an environment variable for the deploy step — never logged.

---

## 28. Tagging Strategy

Every resource gets `local.common_tags`:
```hcl
common_tags = {
  Environment = local.workspace_env   # "dev" or "prod"
  Project     = "AgriConnect"
  ManagedBy   = "Terraform"
  Owner       = "Asad"
}
```

Applied via `merge()`:
```hcl
resource "aws_vpc" "main" {
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"   # resource-specific tag
  })
}
```

**`merge()` function:** Combines two maps. The second map's keys override the first's. This lets you keep common tags while adding resource-specific ones.

**Why tags matter:**
- Cost allocation: filter AWS Cost Explorer by `Environment=dev` to see dev costs
- Resource discovery: `aws ec2 describe-instances --filters Name=tag:Project,Values=AgriConnect`
- Cleanup: find and destroy all resources tagged `Environment=dev`
- Access control: IAM policies can restrict actions based on tags

---

## 29. Advanced Concepts Used in This Project

### jsonencode()
Converts HCL maps/lists to JSON strings (required for IAM policies, SQS policies):
```hcl
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{ Effect = "Allow", Action = "s3:GetObject" }]
})
```

### trimsuffix()
```hcl
value = "${trimsuffix(aws_apigatewayv2_stage.farmbot.invoke_url, "/")}/chat"
```
Removes trailing slash from the URL before appending `/chat`. Without this: `https://api.aws.com//chat`.

### path.module
```hcl
source_file = "${path.module}/../lambda/weather-alert-processor/index.js"
```
Refers to the directory of the current module's `.tf` file. Portable — works regardless of where Terraform is run from.

### concat()
```hcl
subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)
# merges two lists: ["subnet-pub-1", "subnet-pub-2", "subnet-priv-1", "subnet-priv-2"]
```

### toset()
```hcl
for_each = toset(["auth", "marketplace", "order"])
# converts list to set (removes duplicates, enables for_each)
```

### replace()
```hcl
"${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
# removes "https://" prefix for OIDC condition keys
```

### Template Functions in output values
```hcl
value = "${var.eks_node_desired_size}x ${var.eks_node_instance_type} = ~$${var.eks_node_desired_size * 15}/mo"
# `$$` escapes the dollar sign to prevent interpolation
```

---

## 30. What Could Have Been Done Differently

### Alternative: Terragrunt
Terragrunt wraps Terraform to add DRY configuration across multiple environments. Instead of `terraform.tfvars` per environment, you have a `terragrunt.hcl` hierarchy. Better for multi-account, multi-region setups. Overkill for single-region single-account.

### Alternative: Remote Modules from Terraform Registry
Instead of writing custom modules:
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
  # ... inputs
}
```
The community `terraform-aws-modules/vpc` module is battle-tested. The trade-off: less control, dependency on external maintainer.

### Alternative: Aurora Serverless v2 Instead of RDS
```hcl
resource "aws_rds_cluster" "main" {
  engine_mode = "provisioned"
  serverlessv2_scaling_configuration {
    min_capacity = 0.5    # scales to near-zero when idle
    max_capacity = 2.0
  }
}
```
Scales to near-zero when not in use — dramatically cheaper for dev. More expensive at peak than fixed-size RDS.

### Alternative: VPC Endpoints Instead of NAT Gateway
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.networking.vpc_id
  service_name = "com.amazonaws.ap-south-1.s3"
  route_table_ids = [module.networking.private_route_table_id]
}
```
Private subnet pods calling S3 or SQS don't go through NAT Gateway — they go directly through the VPC endpoint. Cuts NAT data transfer costs significantly. Identified in `cost_estimation` output.

### Alternative: EKS Fargate Instead of Managed Node Groups
No EC2 nodes to manage — pods run as Fargate tasks. No patching, no node sizing decisions. But: no DaemonSets, no GPU support, costs more per pod-hour.

### Alternative: GitHub OIDC Instead of IAM Access Keys
Currently CI uses `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` stored as GitHub Secrets. A more modern approach:
```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
```
GitHub Actions gets temporary credentials via OIDC — no long-lived keys to rotate or leak. The same IRSA pattern but for CI runners instead of pods.

### Alternative: Terraform Cloud Instead of S3 Backend
HashiCorp Terraform Cloud provides remote state, locking, run history, team access controls, and a UI. Free tier for small teams. The trade-off: vendor dependency, data leaves your AWS account.

---

## Quick Reference — How Everything Connects

```
GitHub Actions (infra-terraform.yml)
  → terraform init     reads: terraform/versions.tf (S3 backend)
  → terraform plan     reads: all .tf files
                       reads: terraform.tfvars (values)
                       reads: TF_VAR_* (secrets from GitHub Secrets)
                       reads: AWS (current state via provider)
                       compares: state file in S3
  → terraform apply    calls: AWS APIs
                       writes: state file to S3 (with lock)

State File (S3)
  contains: all resource IDs, ARNs, outputs
  locked by: .tflock file (same bucket, use_lockfile=true)

After Apply:
  → Outputs written to SSM Parameter Store
  → CI/CD reads SSM to configure kubectl, build frontend
  → ArgoCD reads Helm values (updated by app CI) → syncs to EKS
```

---

*This guide covers the complete Terraform implementation of AgriConnect. Every concept here maps to actual code in `stage-infra/terraform/`.*
