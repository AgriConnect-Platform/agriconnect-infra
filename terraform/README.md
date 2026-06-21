# AgriConnect Terraform Infrastructure

Provisions the complete AgriConnect AWS infrastructure. After `terraform apply` the
following are ready in 10–15 minutes:

- VPC, subnets, NAT gateway, IGW
- Bastion host, Backend EC2, Frontend EC2
- Application Load Balancer with path-based routing
- RDS MySQL (private, single-AZ)
- S3 buckets (produce-images: public, delivery-proofs: private)
- **Imported** (not recreated): Lambda, EventBridge, SNS, SQS, IAM, Secrets Manager

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.5.0 |
| AWS CLI | v2 |
| AWS credentials | configured via `aws configure` or IAM role |

Required AWS permissions: EC2, RDS, ALB, S3, IAM, Lambda, SNS, SQS, EventBridge,
Secrets Manager.

---

## Quick Start

```bash
cd terraform/

# 1. Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # set key_pair_name, rds_password, etc.

# 2. Initialize
terraform init

# 3. Preview changes (imports show as "will be imported")
terraform plan

# 4. Apply
terraform apply
```

`terraform apply` will:
1. Import existing Lambda, EventBridge Scheduler, SNS, SQS, IAM into state
2. Create VPC, subnets, IGW, NAT gateway
3. Create security group
4. Create RDS MySQL (~5 min)
5. Create EC2 instances — UserData installs git and clones the repo only
6. Create ALB + target groups + listener rules
7. Create S3 buckets

**Application setup is fully manual** — see [AFTER-APPLY.md](AFTER-APPLY.md) for the step-by-step guide to install dependencies, run migrations, start PM2, and build the frontend.

---

## Destroy (expensive resources only)

```bash
terraform destroy
```

Resources with `lifecycle { prevent_destroy = true }` are **not** deleted:
- `aws_lambda_function.weather_alert`
- `aws_cloudwatch_event_rule.weather_check`
- `aws_sns_topic.weather_alerts`
- `aws_sns_topic.events`
- `aws_sqs_queue.notifications`
- `aws_sqs_queue.notifications_dlq`
- `aws_iam_role.ec2` and attached policies

To destroy everything including protected resources:
```bash
# Remove prevent_destroy from lifecycle blocks first, then:
terraform destroy
```

---

## Architecture

```
Internet
   │
[ALB]  ←── path-based routing ───────────────┐
   │                                          │
   ├─ /api/auth/*      → Backend:3001        │
   ├─ /api/marketplace/*→ Backend:3002        │
   ├─ /api/orders/*    → Backend:3003        │
   ├─ /api/media/*     → Backend:3004        │
   ├─ /api/notifications/*→ Backend:3005     │
   └─ (default)        → Frontend:80         │
                                              │
Public Subnets:                               │
  [Bastion]  [Frontend EC2]  [ALB nodes]  ───┘
                                              
Private Subnets:
  [Backend EC2]  [RDS MySQL]

EventBridge (6h) → Lambda → SNS WeatherAlerts (email)
                          → SNS Events → SQS → notification-service
```

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `ap-south-1` | AWS region |
| `key_pair_name` | — | **Required** EC2 key pair |
| `rds_password` | — | **Required** RDS master password |
| `ami_id` | Ubuntu 22.04 ap-south-1 | AMI ID (update per region) |
| `backend_instance_type` | `t3.medium` | Backend EC2 size |
| `rds_instance_class` | `db.t3.micro` | RDS instance class |

See [terraform.tfvars.example](terraform.tfvars.example) for all variables.

---

## Outputs

| Output | Description |
|--------|-------------|
| `frontend_url` | `http://<ALB-DNS>` — main app URL |
| `alb_dns_name` | Raw ALB DNS name |
| `backend_private_ip` | Backend EC2 private IP |
| `bastion_public_ip` | Bastion for SSH tunneling |
| `rds_endpoint` | RDS hostname (sensitive) |
| `sns_weather_alerts_arn` | Weather email broadcast topic |
| `sns_events_arn` | Structured events topic |
| `sqs_notifications_url` | SQS queue URL |
| `lambda_arn` | weather-alert-processor ARN |
| `ssh_backend_via_bastion` | Ready-to-use SSH jump command |

---

## SSH Access

```bash
# Bastion
ssh -i your-key.pem ubuntu@$(terraform output -raw bastion_public_ip)

# Backend (via bastion jump)
ssh -i your-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i your-key.pem ubuntu@$(terraform output -raw bastion_public_ip)" \
    ubuntu@$(terraform output -raw backend_private_ip)

# Or use the generated command:
$(terraform output -raw ssh_backend_via_bastion)
```

---

## Cost Estimate (ap-south-1, on-demand)

| Resource | ~Monthly Cost |
|----------|--------------|
| t3.medium (backend) | ~$30 |
| t3.small (frontend) | ~$15 |
| t3.micro (bastion) | ~$8 |
| db.t3.micro RDS | ~$15 |
| ALB | ~$20 |
| NAT Gateway | ~$35 |
| S3 (minimal) | ~$1 |
| **Total** | **~$124/month** |

Stop/terminate instances and the RDS when not in use to reduce costs.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Import fails "resource not found" | Verify exact resource name/ID in AWS Console |
| Backend UserData failing | `ssh` to bastion → `ssh` to backend → `cat /var/log/backend-init.log` |
| RDS unreachable from backend | Check security group 3306 rule + subnet routing |
| ALB health check failing | Wait ~10 min for PM2 services to start; check `/health` manually |
| `prevent_destroy` blocking destroy | Edit lifecycle block temporarily to remove the constraint |
| `filename` error on Lambda import | The `lambda_placeholder.zip` must exist in `terraform/` directory |

---

## Module Structure

```
terraform/
  main.tf              ← root: module calls + import blocks
  variables.tf         ← all input variables
  locals.tf            ← computed locals (account_id, tags)
  outputs.tf           ← all outputs
  versions.tf          ← Terraform + provider version pins
  providers.tf         ← AWS provider + default_tags
  terraform.tfvars.example
  lambda_placeholder.zip  (generated — gitignored)
  modules/
    networking/        ← VPC, subnets, IGW, NAT, route tables
    security/          ← common SG, EC2 IAM role + instance profile
    ec2/               ← bastion, backend, frontend instances
    alb/               ← ALB, target groups, listener rules
    rds/               ← RDS MySQL + subnet group
    s3/                ← produce-images + delivery-proofs buckets
```
