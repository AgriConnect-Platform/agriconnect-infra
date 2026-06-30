# AgriConnect Infrastructure

[![Terraform](https://github.com/AgriConnect-Platform/agriconnect-infra/actions/workflows/infra-terraform.yml/badge.svg?branch=main)](https://github.com/AgriConnect-Platform/agriconnect-infra/actions/workflows/infra-terraform.yml)
[![Bootstrap](https://github.com/AgriConnect-Platform/agriconnect-infra/actions/workflows/bootstrap.yml/badge.svg)](https://github.com/AgriConnect-Platform/agriconnect-infra/actions/workflows/bootstrap.yml)

![Terraform](https://img.shields.io/badge/Terraform-≥1.6-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-ap--south--1-FF9900?logo=amazon-aws&logoColor=white)
![EKS](https://img.shields.io/badge/EKS-1.31-326CE5?logo=kubernetes&logoColor=white)
![Python](https://img.shields.io/badge/Lambda-Python%203.12-3776AB?logo=python&logoColor=white)
![Node.js](https://img.shields.io/badge/Lambda-Node.js%2018-339933?logo=node.js&logoColor=white)

---

This repository provisions the complete AWS infrastructure for the AgriConnect farm-to-market platform. It creates a production-grade Kubernetes environment on EKS, a MySQL database, a CloudFront CDN with WAF protection, three Lambda-powered AI chatbots, SNS/SQS event messaging, Secrets Manager for credentials, and a full GitOps delivery pipeline via ArgoCD. All resources are managed by Terraform in the `ap-south-1` (Mumbai) region, targeting Indian farmers and buyers.

---

## Repository Structure

```
agriconnect-infra/
├── .github/
│   └── workflows/
│       ├── infra-terraform.yml     # Trivy IaC scan → Plan → Apply (with manual gate)
│       └── bootstrap.yml           # Post-apply: LB Controller, ArgoCD, DB migrate, seed
├── AI_AGENTS_GUIDE.md              # Full AI/LLM/agent documentation (65 KB)
├── CAPSTONE_REQUIREMENTS.md        # DevSecOps requirements mapping (80 KB)
├── INFRA_GUIDE.md                  # Infrastructure architecture guide
├── PIPELINE_GUIDE.md               # CI/CD pipeline explanation (69 KB)
├── TERRAFORM_GUIDE.md              # Terraform usage guide
├── lambda/
│   ├── farmbot/                    # FarmBot AI Lambda (Python 3.12, Nova Pro)
│   │   ├── lambda_function.py      # HTTP handler + multimodal image detection
│   │   ├── bedrock_client.py       # Bedrock converse() call + conversation history
│   │   ├── s3_handler.py           # Uploads conversation logs to S3
│   │   ├── sns_handler.py          # Publishes critical disease alerts to SNS
│   │   └── system_prompt.py        # FarmBot system prompt (agricultural advisor)
│   ├── buyerbot/                   # BuyerBot AI Lambda (Python 3.12, Nova Lite)
│   │   ├── lambda_function.py      # HTTP handler + session management
│   │   ├── bedrock_client.py       # ReAct tool-use loop for live marketplace data
│   │   ├── system_prompt.py        # BuyerBot system prompt (buyer assistant)
│   │   └── tools.py                # Tool: fetch /api/marketplace/listings?limit=20
│   └── weather-alert-processor/   # Weather Lambda (Node.js 18.x)
│       ├── index.js                # POSTs to /api/notifications/weather-alert every 6h
│       └── package.json
├── scripts/
│   ├── eks-bootstrap.sh            # Manual EKS setup helper
│   └── tf-bootstrap.sh             # Terraform backend bootstrap helper
└── terraform/
    ├── bootstrap/
    │   └── main.tf                 # One-time: creates S3 state bucket + DynamoDB lock table
    ├── cloudwatch.tf               # 5 CloudWatch alarms + log groups
    ├── environments/
    │   └── dev/main.tf             # Placeholder — delegates to root
    ├── locals.tf                   # Workspace-driven env name + common tags
    ├── main.tf                     # Root: frontend S3, Secrets Manager, SNS, SQS,
    │                               #   Lambda functions, API Gateways, EventBridge,
    │                               #   SSM Parameters, FarmBot logs S3
    ├── modules/
    │   ├── cloudfront/             # WAFv2 + CloudFront distribution
    │   ├── eks/                    # EKS cluster, node group, IRSA roles, ECR repos
    │   ├── networking/             # VPC, subnets, IGW, NAT Gateway, route tables
    │   ├── rds/                    # MySQL 8.0 RDS instance
    │   ├── s3/                     # Produce images S3 bucket
    │   └── security/               # Common SG, Lambda IAM role, Scheduler IAM role
    ├── outputs.tf                  # 17 outputs including URLs, ARNs, credentials hint
    ├── policies/
    │   └── aws-load-balancer-controller.json  # LB controller IAM policy document
    ├── providers.tf                # aws (ap-south-1) + aws.us_east_1 aliases
    ├── scripts/set-account-id.sh  # Helper to set account ID in tfvars
    ├── terraform.tfvars            # Actual variable values (non-sensitive)
    ├── terraform.tfvars.example    # Template for new environments
    ├── variables.tf                # All variable declarations
    └── versions.tf                 # Terraform + provider version constraints + S3 backend
```

---

## Remote State

| Setting | Value |
|---------|-------|
| Backend | S3 |
| Bucket | `agriconnect-tfstate-893431614084` |
| Key | `agriconnect/terraform.tfstate` |
| Region | `ap-south-1` |
| Encryption | `encrypt = true` |
| Locking | Native S3 lock file (`use_lockfile = true`) |

The bootstrap module creates the state bucket (versioning + AES256 SSE + all public access blocked) and a DynamoDB table `agriconnect-terraform-locks` (PAY_PER_REQUEST, hash key: `LockID`). Run this **once** before any other Terraform commands:

```bash
cd terraform/bootstrap
terraform init && terraform apply
```

---

## Providers

| Provider | Version | Region |
|----------|---------|--------|
| `hashicorp/aws` (default) | `~> 5.0` | `ap-south-1` |
| `hashicorp/aws` (alias: `us_east_1`) | `~> 5.0` | `us-east-1` (WAFv2 + CloudFront) |
| `hashicorp/archive` | `~> 2.0` | — |
| Terraform | `>= 1.6.0` | — |

---

## Input Variables

| Variable | Type | Default | Actual Value | Sensitive |
|----------|------|---------|--------------|-----------|
| `aws_region` | string | `ap-south-1` | `ap-south-1` | no |
| `project_name` | string | `agriconnect` | `agriconnect` | no |
| `vpc_cidr` | string | `10.0.0.0/16` | `10.0.0.0/16` | no |
| `public_subnet_cidrs` | list | `["10.0.1.0/24","10.0.2.0/24"]` | same | no |
| `private_subnet_cidrs` | list | `["10.0.10.0/24","10.0.11.0/24"]` | same | no |
| `availability_zones` | list | `["ap-south-1a","ap-south-1b"]` | same | no |
| `rds_db_name` | string | `agriconnect` | `agriconnect` | no |
| `rds_username` | string | `admin` | `admin` | yes |
| `rds_password` | string | (required) | GitHub Secret `TF_VAR_RDS_PASSWORD` | yes |
| `s3_produce_images_bucket` | string | (required) | `agriconnect-produce-images-893431614084` | no |
| `farmbot_logs_bucket` | string | `agriconnect-farmbot-logs` | same | no |
| `smtp_host` | string | `smtp.gmail.com` | `smtp.gmail.com` | no |
| `smtp_port` | number | `587` | `587` | no |
| `smtp_user` | string | `""` | `asadchamp109@gmail.com` | yes |
| `smtp_pass` | string | `""` | GitHub Secret `TF_VAR_SMTP_PASS` | yes |
| `smtp_from` | string | `""` | `AgriConnect <asadchamp109@gmail.com>` | no |
| `jwt_secret` | string | (required) | GitHub Secret `TF_VAR_JWT_SECRET` | yes |
| `jwt_expiry` | string | `24h` | `24h` | no |
| `admin_email` | string | `""` | `asadchamp109@gmail.com` | no |
| `weather_schedule_expression` | string | `rate(6 hours)` | `rate(6 hours)` | no |
| `eks_node_instance_type` | string | `t3.medium` | `t3.medium` | no |
| `eks_node_desired_size` | number | `2` | `2` | no |
| `eks_node_min_size` | number | `2` | `2` | no |
| `eks_node_max_size` | number | `4` | `4` | no |
| `eks_alb_dns_name` | string | `""` | `k8s-producti-agriconn-86a24bc09e-1038615273.ap-south-1.elb.amazonaws.com` | no |

**Workspace-driven configuration:**

| Setting | `default` workspace (dev) | `prod` workspace |
|---------|--------------------------|-----------------|
| `name_prefix` | `agriconnect-dev` | `agriconnect-prod` |
| `rds_instance_class` | `db.t3.micro` | `db.t3.small` |
| `rds_allocated_storage` | 20 GB | 50 GB |

---

## Outputs

| Output | Value | Sensitive |
|--------|-------|-----------|
| `cloudfront_url` | `https://<cloudfront-domain>` | no |
| `frontend_bucket` | `agriconnect-frontend-893431614084` | no |
| `cloudfront_distribution_id` | CloudFront distribution ID | no |
| `eks_cluster_name` | `agriconnect-dev-eks` | no |
| `eks_cluster_endpoint` | EKS API endpoint URL | no |
| `eks_kubeconfig_command` | `aws eks update-kubeconfig --name agriconnect-dev-eks --region ap-south-1` | no |
| `eks_services_irsa_role_arn` | `arn:aws:iam::893431614084:role/agriconnect-dev-eks-services-role` | no |
| `eks_lb_controller_role_arn` | LB controller IRSA role ARN | no |
| `eks_ecr_registry` | `893431614084.dkr.ecr.ap-south-1.amazonaws.com` | no |
| `eks_alb_dns_name` | ALB DNS name | no |
| `rds_endpoint` | RDS hostname | **yes** |
| `sns_events_arn` | `AgriConnect-Events` topic ARN | no |
| `sqs_notifications_url` | `AgriConnect-Notifications-Queue` URL | no |
| `farmbot_api_url` | FarmBot API Gateway URL + `/chat` | no |
| `buyerbot_api_url` | BuyerBot API Gateway URL + `/chat` | no |
| `secret_database_arn` | Secrets Manager ARN for DB credentials | no |
| `cost_estimation` | Map of estimated monthly costs per service | no |

---

## AWS Resources Created

### Networking (`modules/networking`)

| Resource | Name | Configuration |
|----------|------|---------------|
| VPC | `agriconnect-dev-vpc` | CIDR `10.0.0.0/16`, DNS support + hostnames enabled |
| Internet Gateway | `agriconnect-dev-igw` | Attached to VPC |
| Public Subnet 1 | `agriconnect-dev-public-1` | `10.0.1.0/24`, AZ `ap-south-1a`, `map_public_ip_on_launch = true` |
| Public Subnet 2 | `agriconnect-dev-public-2` | `10.0.2.0/24`, AZ `ap-south-1b`, `map_public_ip_on_launch = true` |
| Private Subnet 1 | `agriconnect-dev-private-1` | `10.0.10.0/24`, AZ `ap-south-1a` |
| Private Subnet 2 | `agriconnect-dev-private-2` | `10.0.11.0/24`, AZ `ap-south-1b` |
| Elastic IP | `agriconnect-dev-nat-eip` | `domain = "vpc"` |
| NAT Gateway | `agriconnect-dev-nat` | Single NAT in `10.0.1.0/24` (public-1) |
| Public Route Table | `agriconnect-dev-rt-public` | Default route → IGW |
| Private Route Table | `agriconnect-dev-rt-private` | Default route → NAT Gateway |

### Security (`modules/security`)

| Resource | Name | Key Rules |
|----------|------|-----------|
| Security Group | `AgriConnect-Common-SG` | Ingress: TCP 80 (`0.0.0.0/0`), TCP 443 (`0.0.0.0/0`), TCP 3306 (`10.0.0.0/16`). Egress: all. |
| IAM Role | `AgriConnectLambdaRole` | Trusted by `lambda.amazonaws.com`. Policy: `logs:*` on all CloudWatch, `sns:Publish` on `*`. |
| IAM Role | `AgriConnectSchedulerRole` | Trusted by `scheduler.amazonaws.com`. Policy: `lambda:InvokeFunction` on `*`. |

### RDS (`modules/rds`)

| Resource | Name | Configuration |
|----------|------|---------------|
| DB Subnet Group | `agriconnect-dev-db-subnet-group` | Private subnets only |
| RDS Instance | `agriconnect-dev-mysql` | Engine: MySQL 8.0 · Class: `db.t3.micro` (dev) / `db.t3.small` (prod) · Storage: 20 GB (dev) / 50 GB (prod) · DB: `agriconnect` · User: `admin` · `publicly_accessible = false` · `multi_az = false` · `skip_final_snapshot = true` · `deletion_protection = false` |

### S3 (`modules/s3`)

| Bucket | Configuration |
|--------|---------------|
| `agriconnect-produce-images-893431614084` | Public read policy · CORS: GET/PUT/POST/DELETE from `*` · `max_age_seconds = 3000` |

### EKS (`modules/eks`)

| Resource | Name | Configuration |
|----------|------|---------------|
| IAM Role (cluster) | `agriconnect-dev-eks-cluster-role` | Trusted by `eks.amazonaws.com` · Policy: `AmazonEKSClusterPolicy` |
| IAM Role (node) | `agriconnect-dev-eks-node-role` | Trusted by `ec2.amazonaws.com` · Policies: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy` |
| EKS Cluster | `agriconnect-dev-eks` | Version: `1.31` · Public + private endpoint · All control plane log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) |
| EKS Node Group | `agriconnect-dev-nodes` | Instance: `t3.medium` · Desired/Min: 2 · Max: 4 · Private subnets · `max_unavailable = 1` · Tagged for cluster-autoscaler |
| CloudWatch Log Group | `/aws/eks/agriconnect-dev-eks/cluster` | Retention: 30 days |
| EKS Addon | `amazon-cloudwatch-observability` | Container Insights |
| OIDC Provider | (derived from cluster) | Client: `sts.amazonaws.com` |
| IRSA Role (services) | `agriconnect-dev-eks-services-role` | Trust: `system:serviceaccount:production:agriconnect-services` + `system:serviceaccount:dev:agriconnect-services` · Permissions: Secrets Manager `GetSecretValue/DescribeSecret` on `arn:aws:secretsmanager:*:893431614084:secret:agriconnect/*`; `sns:Publish` on `*`; SQS Send/Receive/Delete/GetAttributes on `*`; S3 Get/Put/Delete/List on `arn:aws:s3:::agriconnect-*` |
| IRSA Role (LB controller) | `agriconnect-dev-eks-lb-controller-role` | Trust: `system:serviceaccount:kube-system:aws-load-balancer-controller` |
| IAM Policy (LB controller) | `agriconnect-dev-AWSLoadBalancerControllerIAMPolicy` | Full ALB controller permissions (EC2, ELB, WAF, ACM, Cognito, Shield) |
| IRSA Role (autoscaler) | `agriconnect-dev-cluster-autoscaler-role` | Trust: `system:serviceaccount:kube-system:cluster-autoscaler` · ASG describe/scale with cluster tag conditions |
| ECR Repository ×5 | `agriconnect-auth/marketplace/order/media/notification` | `image_tag_mutability = MUTABLE` · Scan on push · Lifecycle: keep last 10 images |
| SG Rule (nodes→RDS) | — | Ingress TCP 3306 from EKS node SG to `AgriConnect-Common-SG` |

### CloudFront (`modules/cloudfront`)

| Resource | Name / Configuration |
|----------|----------------------|
| WAFv2 Web ACL | `agriconnect-waf` (in `us-east-1`, scope: `CLOUDFRONT`) · Default action: allow |
| WAF Rule 0 | `AllowMediaUploads` (priority 0) — Allow `/api/media/upload*` before WAF inspection |
| WAF Rule 1 | `AWSManagedRulesCommonRuleSet` (priority 1) — SQL, XSS, LFI. `SizeRestrictions_BODY` overridden to COUNT (not block) for image uploads. |
| WAF Rule 2 | `AWSManagedRulesKnownBadInputsRuleSet` (priority 2) — Log4Shell, exploit signatures |
| WAF Rule 3 | `RateLimitLogin` (priority 3) — Block >100 requests/IP/5min to `/api/auth/login` |
| WAF Rule 4 | `GlobalRateLimit` (priority 4) — Block >2000 requests/IP/5min globally |
| CloudFront Distribution | Comment: "AgriConnect - S3 frontend + ALB API with WAF" · `price_class = PriceClass_All` · IPv6 enabled · WAF attached |
| Origin: `s3-frontend` | S3 website endpoint, `http-only` |
| Origin: `alb-origin` | ALB DNS, `http-only`, custom header `X-Forwarded-By: CloudFront` |
| Behaviour `/api/*` | → ALB · No cache (min/default/max TTL = 0) · All headers + cookies + query strings forwarded · HTTP→HTTPS redirect |
| Behaviour `/assets/*` | → S3 · Aggressive cache (default 86400s / max 31536000s) · No cookies/headers |
| Default behaviour | → S3 · Short cache (max 300s) · SPA mode |
| Error responses | 404 → 200 `/index.html` · 403 → 200 `/index.html` |

### Root Resources (`main.tf`)

**Frontend S3:**

| Bucket | Configuration |
|--------|---------------|
| `agriconnect-frontend-893431614084` | `force_destroy = true` · Public read · Website: index/error → `index.html` |

**Secrets Manager** (`recovery_window_in_days = 0`):

| Secret Name | Contents |
|-------------|----------|
| `agriconnect/dev/database` | `{ host, port: 3306, database: "agriconnect", username: "admin", password }` |
| `agriconnect/dev/jwt` | `{ jwt_secret, jwt_expiry: "24h" }` |
| `agriconnect/dev/aws` | `{ access_key: "USE_IRSA", secret_key: "USE_IRSA", region: "ap-south-1" }` |
| `agriconnect/dev/email` | `{ host, port: 587, user, pass, from }` |
| `agriconnect/dev/s3` | `{ produce_bucket, region }` |

**SNS Topics:**

| Topic Name | Purpose |
|------------|---------|
| `AgriConnect-MonitoringAlerts` | CloudWatch alarms → email (admin_email) |
| `AgriConnect-WeatherAlerts` | Weather alert emails → admin_email |
| `AgriConnect-Events` | Structured app events → SQS |
| `farmbot-critical-alerts` | FarmBot critical disease detections → email |

**SQS Queues:**

| Queue | Configuration |
|-------|---------------|
| `AgriConnect-Notifications-Queue` | `visibility_timeout = 30s` · `retention = 86400s` (1 day) · `receive_wait = 20s` · DLQ after 3 failures |
| `AgriConnect-Notifications-DLQ` | `retention = 1209600s` (14 days) |

**Lambda Functions:**

| Function | Runtime | Timeout | Memory | Model | Handler |
|----------|---------|---------|--------|-------|---------|
| `weather-alert-processor` | Node.js 18.x | 60s | default | — | `index.handler` |
| `farmbot-chatbot` | Python 3.12 | 30s | default | `amazon.nova-pro-v1:0` | `lambda_function.lambda_handler` |
| `buyerbot-chatbot` | Python 3.12 | 60s | default | `amazon.nova-lite-v1:0` | `lambda_function.lambda_handler` |

**API Gateways (HTTP v2, auto-deploy):**

| API Name | Route | Target | CORS |
|----------|-------|--------|------|
| `farmbot-api` | `POST /chat` | farmbot Lambda | `*`, POST + OPTIONS |
| `buyerbot-api` | `POST /chat` | buyerbot Lambda | `*`, POST + OPTIONS |

**EventBridge Scheduler:**

| Name | Schedule | Timezone | Target |
|------|----------|----------|--------|
| `agriconnect-weather-check` | `rate(6 hours)` | `Asia/Kolkata` | `weather-alert-processor` Lambda |

**SSM Parameters:**

| Parameter | Value |
|-----------|-------|
| `/agriconnect/farmbot-api-url` | FarmBot API Gateway URL |
| `/agriconnect/buyerbot-api-url` | BuyerBot API Gateway URL |
| `/agriconnect/cloudfront-distribution-id` | CloudFront distribution ID |
| `/agriconnect/eks-cluster-name` | `agriconnect-dev-eks` |
| `/agriconnect/eks-services-irsa-role-arn` | Services IRSA role ARN |
| `/agriconnect/eks-lb-controller-role-arn` | LB controller IRSA role ARN |
| `/agriconnect/public-subnet-ids` | Public subnet IDs |
| `/agriconnect/cluster-autoscaler-role-arn` | Cluster autoscaler role ARN |
| `/agriconnect/alb-dns-name` | ALB DNS (written post-bootstrap) |

**FarmBot S3:**

| Bucket | Configuration |
|--------|---------------|
| `agriconnect-farmbot-logs` | `force_destroy = true` · Fully private (all public access blocked) |

### CloudWatch Alarms

All alarms notify `AgriConnect-MonitoringAlerts` SNS topic:

| Alarm | Metric | Namespace | Threshold | Eval |
|-------|--------|-----------|-----------|------|
| `agriconnect-dev-rds-cpu-high` | `CPUUtilization` | `AWS/RDS` | > 80% | 2 × 5 min |
| `agriconnect-dev-rds-storage-low` | `FreeStorageSpace` | `AWS/RDS` | < 2 GB | 1 × 5 min |
| `agriconnect-dev-eks-node-cpu-high` | `node_cpu_utilization` | ContainerInsights | > 85% | 2 × 5 min |
| `agriconnect-dev-eks-node-memory-high` | `node_memory_utilization` | ContainerInsights | > 85% | 2 × 5 min |
| `agriconnect-dev-eks-pod-restart-high` | `pod_number_of_container_restarts` | ContainerInsights | > 1 (Sum) | 1 × 5 min |

**CloudWatch Log Groups (all retention = 30 days):**

- `/aws/eks/agriconnect-dev-eks/cluster`
- `/aws/containerinsights/<cluster>/application`
- `/aws/containerinsights/<cluster>/dataplane`
- `/aws/lambda/weather-alert-processor`
- `/aws/lambda/farmbot-chatbot`
- `/aws/lambda/buyerbot-chatbot`

---

## Lambda Functions — Detail

### FarmBot (`lambda/farmbot/`)

AI agricultural advisor for Indian farmers. Uses `amazon.nova-pro-v1:0` via `bedrock.converse()`. Supports multimodal input (crop photos + text):
- Detects image format automatically (PNG/JPEG/GIF/WEBP)
- Enforces 3 MB image limit; 5 MB `MAX_IMAGE_SIZE_MB` env var
- Maintains conversation history: last **4 turns** with image, last **20 turns** text-only
- Returns `{ response, critical }` where `critical = true` if image + disease keywords (blight, wilt, rot, rust) are detected
- On `critical = true`: publishes to `farmbot-critical-alerts` SNS topic + logs conversation to `agriconnect-farmbot-logs` S3

**Environment variables:**

| Variable | Value |
|----------|-------|
| `BEDROCK_REGION` | `us-east-1` |
| `MODEL_ID` | `amazon.nova-pro-v1:0` |
| `S3_BUCKET_NAME` | `agriconnect-farmbot-logs` |
| `SNS_TOPIC_ARN` | `farmbot-critical-alerts` ARN |
| `MAX_IMAGE_SIZE_MB` | `5` |

### BuyerBot (`lambda/buyerbot/`)

Marketplace buyer assistant. Uses `amazon.nova-lite-v1:0` via `bedrock.converse()` with tool use:
- Fetches live listings from `http://<ALB_URL>/api/marketplace/listings?limit=20` using a Bearer token from the request body
- Builds dynamic system prompt with up to 15 live listings (name, price, quantity, farm name, location)
- Falls back to general Indian wholesale price knowledge if ALB unavailable

**Environment variables:**

| Variable | Value |
|----------|-------|
| `BEDROCK_REGION` | `us-east-1` |
| `MODEL_ID` | `amazon.nova-lite-v1:0` |
| `ALB_URL` | Set post-bootstrap via SSM |

### Weather Alert Processor (`lambda/weather-alert-processor/`)

Node.js 18 function triggered every 6 hours by EventBridge Scheduler (timezone: `Asia/Kolkata`). Picks one of 4 alert messages based on UTC hour (rain, heat, storm, default), then POSTs to `http://<ALB_URL>/api/notifications/weather-alert` with `{ message, alert_type }`.

**Environment variables:**

| Variable | Value |
|----------|-------|
| `SNS_TOPIC_ARN` | `AgriConnect-WeatherAlerts` ARN |
| `EVENTS_TOPIC_ARN` | `AgriConnect-Events` ARN |
| `ALB_URL` | ALB DNS — set post-bootstrap |

---

## GitHub Actions Workflows

### `infra-terraform.yml`

**Trigger:** Push to `main` on paths `terraform/**`, `lambda/**`, `.github/workflows/infra-terraform.yml`, or manual `workflow_dispatch`.

**Job 1 — `scan`** (Trivy IaC):
```
trivy config terraform/ --severity CRITICAL,HIGH --exit-code 0
```

**Job 2 — `plan`** (needs: scan):
```
aws-actions/configure-aws-credentials@v4  (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)
hashicorp/setup-terraform@v3
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=terraform.tfvars -out=tfplan
  (env: TF_VAR_rds_password, TF_VAR_jwt_secret, TF_VAR_smtp_pass)
Upload artifacts: tfplan, lambda_package.zip, farmbot_package.zip, buyerbot_package.zip
  (retention: 1 day)
```

**Job 3 — `apply`** (needs: plan; environment: `production` — **manual approval gate**):
```
Download plan artifact
terraform apply tfplan
```

### `bootstrap.yml`

**Trigger:** Manual `workflow_dispatch` only. Run **once** after `terraform apply`.

**Steps (in order):**

| Step | Action |
|------|--------|
| 1 | Verify ECR images exist for all 5 services — aborts if any repo empty |
| 2 | Read SSM params: cluster name, LB role, IRSA role, autoscaler role, subnet IDs, CloudFront distribution ID |
| 3 | `aws eks update-kubeconfig --name agriconnect-dev-eks --region ap-south-1` |
| 4 | Install AWS Load Balancer Controller via Helm (`eks/aws-load-balancer-controller`) |
| 5 | Install ArgoCD (stable manifest, server-side apply); wait for all components ready |
| 6 | Configure ArgoCD repo access (Secret for `https://github.com/AgriConnect-Platform/agriconnect-helm.git` using `GH_PAT`) |
| 7 | Apply `argocd/application.yaml` (dev → `production` NS) + `argocd/application-prod.yaml` (prod → `prod` NS) |
| 8 | ArgoCD diagnostics (repo secret, logs, app conditions) |
| 9 | Force ArgoCD hard refresh + immediate sync |
| 10 | Wait up to 5 min for Sync=Synced + Health=Healthy |
| 11 | Wait for ALB DNS: `kubectl get ingress agriconnect-ingress -n production` |
| 12 | Update CloudFront origin to new ALB (Python boto3) |
| 13 | Store ALB URL in SSM `/agriconnect/alb-dns-name`; update weather + buyerbot Lambda env vars with `ALB_URL` |
| 14 | Run DB migration: pod with `auth-service` image → `node /app/shared/scripts/migrate.js`; wait for `Succeeded` |
| 15 | Run DB seed: pod → `node /app/shared/scripts/seed.js` |
| 16 | Install Metrics Server (Helm, `--kubelet-insecure-tls`) |
| 17 | Install Cluster Autoscaler (Helm v1.31.0, `expander=least-waste`, scale-down-delay=2m, scale-down-unneeded-time=2m) |
| 18 | Cleanup migration/seed pods |
| 19 | Print summary: CloudFront URL, ALB URL, default credentials |

---

## Required GitHub Secrets and Variables

| Secret | Required By | Description |
|--------|-------------|-------------|
| `AWS_ACCESS_KEY_ID` | Both workflows | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Both workflows | AWS secret key |
| `TF_VAR_RDS_PASSWORD` | infra-terraform.yml | MySQL root password |
| `TF_VAR_JWT_SECRET` | infra-terraform.yml | JWT signing secret |
| `TF_VAR_SMTP_PASS` | infra-terraform.yml | Gmail app password |
| `GH_PAT` | bootstrap.yml | GitHub PAT to read helm repo from ArgoCD |

---

## Deployment Walkthrough

### Full From-Scratch Deployment

```bash
# 1. Bootstrap remote state (run once)
cd terraform/bootstrap
terraform init
terraform apply
# Creates: S3 bucket agriconnect-tfstate-893431614084, DynamoDB table agriconnect-terraform-locks

# 2. Set your account ID in tfvars
bash scripts/set-account-id.sh

# 3. Set sensitive variables as environment variables
export TF_VAR_rds_password="<your-rds-password>"
export TF_VAR_jwt_secret="<your-jwt-secret>"
export TF_VAR_smtp_pass="<gmail-app-password>"

# 4. Initialise Terraform
terraform init

# 5. Validate + plan
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=terraform.tfvars -out=tfplan

# 6. Apply (creates ~60+ AWS resources)
terraform apply tfplan
# Takes ~20 minutes (EKS cluster creation dominates)

# 7. Build and push at least one image per ECR repo
# (Bootstrap step 1 verifies these exist)
aws ecr get-login-password --region ap-south-1 | docker login --username AWS \
  --password-stdin 893431614084.dkr.ecr.ap-south-1.amazonaws.com
docker build -t agriconnect-auth ./path/to/auth-service
docker tag agriconnect-auth:latest 893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-auth:latest
docker push 893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-auth:latest
# Repeat for marketplace, order, media, notification

# 8. Run bootstrap workflow (GitHub Actions → manual dispatch)
# This installs ArgoCD, LB Controller, applies ArgoCD apps,
# runs DB migration + seed, installs Metrics Server + Cluster Autoscaler

# 9. Get your platform URL
terraform output cloudfront_url
```

### Connect to Kubernetes

```bash
aws eks update-kubeconfig --name agriconnect-dev-eks --region ap-south-1
kubectl get pods -n production
kubectl get ingress -n production
```

---

## Resource Inventory

| Resource Type | Count | Key Names |
|---------------|-------|-----------|
| VPC | 1 | `agriconnect-dev-vpc` (`10.0.0.0/16`) |
| Subnets | 4 | 2 public (`10.0.1/2.0/24`) + 2 private (`10.0.10/11.0/24`) |
| NAT Gateway | 1 | `agriconnect-dev-nat` (single, in ap-south-1a) |
| Security Groups | 1 | `AgriConnect-Common-SG` |
| EKS Cluster | 1 | `agriconnect-dev-eks` (v1.31) |
| EKS Node Group | 1 | `t3.medium`, 2–4 nodes |
| ECR Repositories | 5 | auth, marketplace, order, media, notification |
| RDS Instance | 1 | MySQL 8.0, `db.t3.micro`, 20 GB |
| S3 Buckets | 3 | frontend, produce-images, farmbot-logs |
| CloudFront Distribution | 1 | With WAFv2 Web ACL (5 rules) |
| Lambda Functions | 3 | farmbot, buyerbot, weather-alert-processor |
| API Gateways | 2 | farmbot-api, buyerbot-api |
| SNS Topics | 4 | MonitoringAlerts, WeatherAlerts, Events, farmbot-critical |
| SQS Queues | 2 | Notifications queue + DLQ |
| Secrets Manager Secrets | 5 | database, jwt, aws, email, s3 |
| EventBridge Scheduler | 1 | 6-hour weather alert |
| IAM Roles | 7 | cluster, node, IRSA×4, scheduler |
| SSM Parameters | 9 | API URLs, cluster info, subnet IDs |
| CloudWatch Alarms | 5 | RDS CPU, RDS storage, EKS CPU, EKS memory, pod restarts |
| CloudWatch Log Groups | 6 | EKS + Lambda |

---

## Cost Estimate

| Resource | Est. Monthly Cost |
|----------|------------------|
| EKS control plane | ~$72 |
| EKS nodes (2× t3.medium) | ~$30 |
| NAT Gateway + data transfer | ~$33+ |
| ALB | ~$18 |
| RDS `db.t3.micro` + 20 GB | ~$15 |
| CloudFront (low traffic) | ~$1–5 |
| S3 (3 buckets) | ~$2–5 |
| Lambda (pay-per-request) | ~$0–2 |
| SNS + SQS | ~$0–1 |
| Secrets Manager | ~$2 |
| CloudWatch (30-day retention) | ~$1–3 |
| **Total** | **~$175–190/month** |

> **Cost tip:** EKS nodes + NAT Gateway account for ~70% of total cost. Add VPC endpoints for S3 and SQS to reduce NAT data transfer charges.
