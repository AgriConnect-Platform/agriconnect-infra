# AgriConnect — Complete Infrastructure Explanation

> Every cloud service, how it works, why it exists, and how your application uses it.
> From a user opening the browser to the database responding — every hop explained.

---

## Table of Contents

1. [The Big Picture — What You Built](#1-the-big-picture--what-you-built)
2. [How a User Request Flows Through the System](#2-how-a-user-request-flows-through-the-system)
3. [VPC — Your Private Network in AWS](#3-vpc--your-private-network-in-aws)
4. [CloudFront — The Front Door](#4-cloudfront--the-front-door)
5. [WAF — Security Guard at the Door](#5-waf--security-guard-at-the-door)
6. [S3 — Where Your React App Lives](#6-s3--where-your-react-app-lives)
7. [ALB — Traffic Cop for Your APIs](#7-alb--traffic-cop-for-your-apis)
8. [EKS — Your Kubernetes Cluster](#8-eks--your-kubernetes-cluster)
9. [The 5 Microservices Inside EKS](#9-the-5-microservices-inside-eks)
10. [RDS — Your Database](#10-rds--your-database)
11. [Secrets Manager — Password Vault](#11-secrets-manager--password-vault)
12. [ECR — Where Your Docker Images Live](#12-ecr--where-your-docker-images-live)
13. [SNS — The Announcement System](#13-sns--the-announcement-system)
14. [SQS — The Task Queue](#14-sqs--the-task-queue)
15. [Lambda — Serverless Functions (Deep Dive)](#15-lambda--serverless-functions-deep-dive)
16. [API Gateway — Lambda's Front Door](#16-api-gateway--lambdas-front-door)
17. [Amazon Bedrock — The AI Brain](#17-amazon-bedrock--the-ai-brain)
18. [EventBridge — The Cron Job Scheduler](#18-eventbridge--the-cron-job-scheduler)
19. [CloudWatch — Monitoring and Alerts](#19-cloudwatch--monitoring-and-alerts)
20. [SSM Parameter Store — Configuration Registry](#20-ssm-parameter-store--configuration-registry)
21. [IRSA — How Pods Access AWS Without Passwords](#21-irsa--how-pods-access-aws-without-passwords)
22. [NAT Gateway — Private Subnet Internet Access](#22-nat-gateway--private-subnet-internet-access)
23. [How the Frontend Gets Deployed to S3](#23-how-the-frontend-gets-deployed-to-s3)
24. [How Lambda Code Gets Deployed (The ZIP Story)](#24-how-lambda-code-gets-deployed-the-zip-story)
25. [Complete End-to-End Flows](#25-complete-end-to-end-flows)

---

## 1. The Big Picture — What You Built

AgriConnect is a marketplace where farmers list produce and buyers purchase it. Here is every AWS service you are running and what category it belongs to:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        INTERNET (Users)                                  │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                    ┌─────▼──────┐
                    │  CloudFront │  ← CDN + WAF + HTTPS termination
                    │   + WAF     │
                    └──┬──────┬──┘
                       │      │
              ┌────────▼──┐  ┌▼────────────┐
              │  S3 Bucket │  │     ALB      │  ← routes /api/* to services
              │ (React App)│  │ (Port 80)    │
              └────────────┘  └──────┬───────┘
                                     │
                    ┌────────────────▼─────────────────────┐
                    │         EKS Cluster (Kubernetes)       │
                    │  ┌──────────────────────────────────┐ │
                    │  │        production namespace       │ │
                    │  │  auth   market  order  media  ntf │ │
                    │  └──────────────┬───────────────────┘ │
                    └─────────────────┼──────────────────────┘
                                      │
              ┌───────────────────────┼──────────────────────────┐
              │                       │                           │
        ┌─────▼────┐           ┌──────▼──────┐           ┌──────▼──────┐
        │   RDS    │           │  Secrets    │           │  S3 Bucket  │
        │  MySQL   │           │  Manager    │           │ (Images)    │
        └──────────┘           └─────────────┘           └─────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    SERVERLESS LAYER (outside EKS)                        │
│                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────────────────┐ │
│  │  API Gateway│    │  API Gateway│    │     EventBridge Scheduler    │ │
│  │  (FarmBot)  │    │  (BuyerBot) │    │     (every 6 hours)          │ │
│  └──────┬──────┘    └──────┬──────┘    └──────────────┬───────────────┘ │
│         │                  │                           │                 │
│  ┌──────▼──────┐    ┌──────▼──────┐    ┌──────────────▼───────────────┐ │
│  │   FarmBot   │    │   BuyerBot  │    │   Weather Alert Lambda        │ │
│  │   Lambda    │    │   Lambda    │    │   (Node.js)                   │ │
│  │  (Python)   │    │  (Python)   │    └──────────────────────────────┘ │
│  └──────┬──────┘    └──────┬──────┘                                     │
│         │                  │                                             │
│  ┌──────▼──────────────────▼──────────────────────────────────────────┐ │
│  │                  Amazon Bedrock (Nova Lite/Pro)                     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    MESSAGING LAYER                                        │
│  SNS (Events) ──► SQS (Notifications Queue) ──► notification-service    │
│  SNS (Weather Alerts) ──► Email (admin)                                  │
│  SNS (FarmBot Critical) ──► Email (admin) / SMS                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY                                          │
│  CloudWatch Logs + 5 Alarms + Container Insights + SNS Alert emails     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. How a User Request Flows Through the System

Let's trace what happens when a farmer opens AgriConnect in their browser and creates a listing:

### Step 1 — Browser makes a request
```
Farmer types: https://d2abc123.cloudfront.net/marketplace
```

### Step 2 — DNS resolves to CloudFront
AWS Route53 (or any DNS) resolves the CloudFront domain to the nearest CloudFront edge server — could be Mumbai, Delhi, or any of 400+ global edge locations.

### Step 3 — WAF inspects the request
Before CloudFront even processes it, WAF checks:
- Is this SQL injection? → Block
- Is this a known bad bot? → Block
- Has this IP hit /api/auth/login more than 100 times in 5 minutes? → Block
- Normal request → Pass through

### Step 4 — CloudFront decides where to send it
- URL is `/marketplace` (no `/api/`) → send to **S3** (React app)
- URL is `/api/marketplace` → send to **ALB** (backend service)

### Step 5a — If going to S3 (page load)
CloudFront fetches `index.html` from S3 bucket. This is the React app shell. React Router takes over in the browser and renders `/marketplace`.

### Step 5b — If going to ALB (API call)
React app (now running in browser) makes `fetch('/api/marketplace/listings')`.
CloudFront sees `/api/*` → forwards to ALB.

### Step 6 — ALB routes to the right pod
ALB reads the URL path:
- `/api/marketplace` → finds the `marketplace-service` pods in EKS
- Picks one of the 2 running pods (round-robin load balancing)

### Step 7 — Pod processes the request
The `marketplace-service` Node.js pod receives the HTTP request.
It fetches DB credentials from Secrets Manager (via IRSA — no password stored in the pod).
It queries RDS MySQL.
Returns JSON response.

### Step 8 — Response travels back
Pod → ALB → CloudFront → Browser. Farmer sees the listings.

---

## 3. VPC — Your Private Network in AWS

**What it is:** A Virtual Private Cloud is your own isolated section of the AWS network. Think of it as your office building — you control who comes in, who goes out, and what rooms people can access.

**Your VPC:** `10.0.0.0/16` (65,536 IP addresses available)

### Subnets — Rooms in Your Building

```
VPC: 10.0.0.0/16
├── Public Subnet A  (10.0.1.0/24)  — ap-south-1a   ← ALB, NAT Gateway
├── Public Subnet B  (10.0.2.0/24)  — ap-south-1b   ← ALB (second AZ)
├── Private Subnet A (10.0.10.0/24) — ap-south-1a   ← EKS nodes, RDS
└── Private Subnet B (10.0.11.0/24) — ap-south-1b   ← EKS nodes, RDS
```

**Public subnets** have a direct route to the internet through the Internet Gateway. Resources here can be reached from the internet (ALB) and can reach the internet directly.

**Private subnets** have NO direct route to the internet. Resources here (EKS pods, RDS) cannot be reached from the internet at all. They can only reach the internet through NAT Gateway.

**Why this separation?**
- Your database should NEVER be reachable from the internet — it sits in the private subnet
- Your pods should NEVER be directly reachable from the internet — they sit in private subnets
- Only the ALB (load balancer) and NAT Gateway sit in public subnets

### Internet Gateway
The door from the public subnet to the internet. The ALB uses this to receive requests from users worldwide.

### Route Tables
Every subnet has a routing table that says "for traffic going to 0.0.0.0/0 (internet), use this gateway":
- Public subnets: use Internet Gateway
- Private subnets: use NAT Gateway

---

## 4. CloudFront — The Front Door

**What it is:** A Content Delivery Network (CDN). It has 400+ servers around the world called "edge locations." When a user makes a request, it goes to the nearest edge location — not all the way to your AWS region in Mumbai.

**Why you need it:**
- A farmer in Pune and one in Delhi both get fast responses from their nearest edge
- Without CloudFront, every request travels to Mumbai (ap-south-1) — adds 100-200ms latency for users far away
- CloudFront also terminates HTTPS, caches static files, and sits in front of WAF

### Your Two Origins

CloudFront is configured with two "origins" — two places it can forward requests to:

**Origin 1: S3 Bucket (Frontend)**
```
URL pattern: everything that's NOT /api/*
→ CloudFront fetches index.html or /assets/file.js from S3
→ Returns it to the user's browser
```

**Origin 2: ALB (Backend API)**
```
URL pattern: /api/*
→ CloudFront forwards the full request to ALB
→ ALB routes to the correct microservice pod
→ Response returned through CloudFront back to browser
```

### Cache Behaviors

| Path | Goes To | Cached? | Why |
|---|---|---|---|
| `/api/*` | ALB | No (0s TTL) | API responses are dynamic — different user, different data |
| `/assets/*` | S3 | 1 year | Vite hashes filenames (app.a3f2c1.js) — same hash = same file forever |
| Everything else | S3 | 5 minutes | index.html changes on deploy |

### SPA (Single Page Application) Routing Fix

React Router handles URLs like `/dashboard`, `/profile`, `/marketplace` in JavaScript. But S3 doesn't have a file called `dashboard`. When a user bookmarks `https://yoursite.com/dashboard` and opens it fresh:

```
Browser → CloudFront → S3: "give me /dashboard"
S3: "I don't have /dashboard" → returns 404
CloudFront: configured to catch 404 → return /index.html with HTTP 200
Browser: gets index.html → React loads → React Router reads URL → shows /dashboard
```

Without this rule, every direct URL access would show a white error page.

### The Custom Header Trick
```
CloudFront adds: X-Forwarded-By: CloudFront
```
Your ALB can verify this header — ensures nobody bypasses CloudFront to hit the ALB directly. This protects WAF from being bypassed.

---

## 5. WAF — Security Guard at the Door

**What it is:** Web Application Firewall. Inspects every HTTP request before it reaches your application. CloudFront passes each request through WAF first.

**Why it must be in us-east-1:** AWS requires all CloudFront-attached WAFs to live in the North Virginia region (us-east-1), even if your application is in ap-south-1. This is why your Terraform has two AWS providers.

### Rules in Your WAF

**Rule 1: AWS Managed Common Rule Set**
Blocks OWASP Top 10 attacks automatically:
- SQL Injection: `' OR 1=1; DROP TABLE users --`
- Cross-Site Scripting: `<script>document.cookie</script>`
- Local File Inclusion: `../../etc/passwd`
- Path traversal attacks

**Rule 2: Known Bad Inputs**
Blocks signatures from known exploits:
- Log4Shell (the 2021 critical vulnerability)
- Spring4Shell
- Known exploit payloads

**Rule 3: Login Rate Limit**
```
/api/auth/login → max 100 requests per IP per 5 minutes
```
Prevents brute-force password attacks. If someone tries 101 login attempts from one IP in 5 minutes, they're blocked.

**Rule 4: Global Rate Limit**
```
Any URL → max 2000 requests per IP per 5 minutes
```
Prevents DoS attacks. Legitimate users never hit 2000 requests in 5 minutes.

---

## 6. S3 — Where Your React App Lives

**What it is:** Simple Storage Service. Object storage — think of it as a hard drive in the cloud where you store files. Any file, any size, accessible via URL.

### Two S3 Buckets in Your Project

**Bucket 1: Frontend (React App)**
```
Bucket name: agriconnect-frontend-893431614084
Purpose: Hosts the compiled React application
```

After `npm run build`, Vite produces:
```
dist/
├── index.html          ← the React app shell
└── assets/
    ├── index.a3f2c1.js   ← all your JavaScript, bundled and minified
    ├── index.9b3d21.css  ← all your CSS
    └── images/...
```

These files are uploaded to S3. CloudFront serves them to users.

**Static website hosting** is enabled on this bucket — S3 serves `index.html` when someone requests `/` or any path that doesn't match a file.

**Bucket 2: Produce Images**
```
Bucket name: agriconnect-produce-images-893431614084
Purpose: Farmers upload photos of their produce
```

When a farmer uploads a photo:
1. media-service pod receives the multipart form upload
2. Pod calls S3 using IRSA credentials (no access keys)
3. Image stored at `s3://agriconnect-produce-images-893431614084/uploads/farmer123/tomatoes.jpg`
4. media-service stores the S3 URL in RDS database
5. marketplace-service reads that URL when showing listings
6. Buyer sees the image loaded from S3 via CloudFront

CORS is enabled on this bucket so the browser can directly upload/fetch images.

---

## 7. ALB — Traffic Cop for Your APIs

**What it is:** Application Load Balancer. It sits in your public subnets and distributes HTTP traffic to your Kubernetes pods in the private subnets.

**What it does:**
1. Receives HTTP requests from CloudFront (for `/api/*`)
2. Reads the URL path
3. Forwards to the correct service in EKS
4. Gets the response and returns it

### Path-Based Routing

Your ingress.yaml in Helm configures the ALB with these rules:

```
/api/auth          →  auth-service pods (port 3001)
/api/marketplace   →  marketplace-service pods (port 3002)
/api/orders        →  order-service pods (port 3003)
/api/media         →  media-service pods (port 3004)
/api/notifications →  notification-service pods (port 3005)
```

The ALB is **not** manually created in Terraform. Instead:
1. You installed the **AWS Load Balancer Controller** in EKS
2. When you deploy the Helm chart, Kubernetes sees the Ingress manifest
3. The LB Controller reads that manifest and automatically calls AWS APIs to create/configure the ALB
4. The ALB DNS is stored in SSM Parameter Store after creation

**Health checks:**
ALB pings `/healthz` on each pod every 30 seconds. If a pod doesn't respond with HTTP 200, the ALB stops sending traffic to it and waits for it to recover.

---

## 8. EKS — Your Kubernetes Cluster

**What it is:** Elastic Kubernetes Service. AWS manages the Kubernetes control plane (the brain of the cluster) — you only pay for and manage the worker nodes (the actual EC2 machines running your pods).

### Your Cluster Configuration

```
Cluster: agriconnect-dev-eks
Region:  ap-south-1
Version: Kubernetes 1.31

Worker Nodes:
  Type:    t3.medium (2 vCPU, 4 GB RAM)
  Count:   2 (minimum) → 4 (maximum, autoscales up under load)
  Where:   Private subnets (ap-south-1a and ap-south-1b)
```

### What "Kubernetes" Actually Does For You

Without Kubernetes, you would need to:
- SSH into EC2 instances and run Docker commands
- Manually restart containers that crash
- Manually balance traffic between servers
- Manually update containers with zero downtime

With Kubernetes (EKS), you just describe what you want:
```yaml
"I want 2 copies of the auth-service container running at all times"
```
Kubernetes ensures this is always true. If one pod crashes, Kubernetes starts a new one. If you push a new image, it does a rolling update (one pod at a time, zero downtime).

### Namespaces

```
production namespace  ←  your live application (2 replicas per service)
dev namespace         ←  test environment (1 replica per service)
```

Pods in `production` and `dev` are completely isolated. Traffic meant for production never reaches dev pods.

### How Your Pods Are Organized

```
production namespace:
├── auth-service        (2 pods × port 3001)
├── marketplace-service (2 pods × port 3002)
├── order-service       (2 pods × port 3003)
├── media-service       (2 pods × port 3004)
└── notification-service(2 pods × port 3005)

Each pod:
├── Docker image from ECR
├── Resources: 100m CPU, 256Mi RAM (request)
│              500m CPU, 512Mi RAM (limit)
├── Health probes: /healthz (liveness), /ready (readiness)
└── ServiceAccount with IRSA role annotation
```

### HPA — Horizontal Pod Autoscaler

Each service has an HPA configured. When CPU usage goes above a threshold, Kubernetes automatically adds more pods. When load drops, it removes them. This means you don't pay for 10 pods when 2 are enough, but you handle traffic spikes automatically.

---

## 9. The 5 Microservices Inside EKS

Each microservice is a Node.js Express application running in a Docker container.

### auth-service (port 3001)
**Handles:** User registration, login, JWT token generation, token validation

**Endpoints:**
- `POST /api/auth/register` — create account
- `POST /api/auth/login` — login, returns JWT
- `GET /api/auth/verify` — validate a JWT token

**On startup:**
1. Fetches `agriconnect/dev/database` from Secrets Manager using IRSA
2. Connects to RDS MySQL
3. Creates tables if they don't exist (Sequelize ORM)

**Flow:**
```
User logs in → auth-service → RDS (check credentials) → return JWT token
All other services validate that JWT for every request
```

### marketplace-service (port 3002)
**Handles:** Farmers listing produce, buyers browsing listings, bidding

**How BuyerBot connects to this:** The BuyerBot Lambda function calls the ALB URL at `/api/marketplace/listings` to get live listing data, then includes that data in Bedrock's context so the AI answers with real prices.

### order-service (port 3003)
**Handles:** Creating orders, order status, payment tracking

**AWS integration:** When an order is placed, it publishes an event to **SNS**:
```javascript
sns.publish({
  TopicArn: process.env.EVENTS_TOPIC_ARN,
  Message: JSON.stringify({ type: 'ORDER_PLACED', orderId, farmerId, buyerId })
})
```
SNS fans this out to SQS, which the notification-service processes.

### media-service (port 3004)
**Handles:** Profile picture uploads, produce image uploads

**How S3 is used:**
```
Farmer uploads image → media-service pod
→ pod calls S3.putObject using IRSA credentials
→ image stored at s3://agriconnect-produce-images-893431614084/uploads/...
→ URL saved in RDS
→ URL returned to frontend
→ Browser loads image directly from CloudFront/S3
```

### notification-service (port 3005)
**Handles:** Real-time notifications to users (order updates, bid alerts)

**The SQS Worker:**
On startup, notification-service launches a background process that polls SQS:
```javascript
// Runs forever in the background
while (true) {
  messages = await sqs.receiveMessage(NOTIFICATIONS_QUEUE_URL)
  for (msg of messages) {
    await sendNotificationToUser(msg)
    await sqs.deleteMessage(msg.ReceiptHandle)
  }
}
```

When order-service publishes to SNS → SNS puts message in SQS → notification-service picks it up → sends notification to the user.

---

## 10. RDS — Your Database

**What it is:** Relational Database Service. A fully managed MySQL database. AWS handles backups, patching, and hardware — you just use it.

**Your config:**
```
Engine:   MySQL 8.0
Instance: db.t3.micro (2 vCPU, 1 GB RAM)
Storage:  20 GB
Location: Private subnets only (NOT accessible from internet)
```

**Your tables (Sequelize models):**
- `Users` — farmer and buyer accounts
- `Farmers` — farmer profile (farm name, location, crops)
- `Buyers` — buyer profile
- `ProduceListings` — what farmers are selling (crop, quantity, price, image URL)
- `Orders` — purchase orders
- `Bids` — buyer bids on listings
- `Transactions` — financial records
- `Payments` — payment status
- `Notifications` — notification history

**How pods connect:**
Pods don't have the database password. They call Secrets Manager on startup:
```javascript
const secret = await secretsManager.getSecretValue({ SecretId: 'agriconnect/dev/database' })
const { host, port, database, username, password } = JSON.parse(secret.SecretString)
// → connects to MySQL with these credentials
```

---

## 11. Secrets Manager — Password Vault

**What it is:** AWS service that stores secrets (passwords, API keys, connection strings) encrypted at rest, with fine-grained access control and automatic rotation support.

### Every Secret in Your Project

```
agriconnect/dev/database → { host, port, database, username, password }
agriconnect/dev/jwt      → { jwt_secret, jwt_expiry }
agriconnect/dev/aws      → { USE_IRSA: "true" }
agriconnect/dev/smtp     → { host, port, user, password, from }
agriconnect/dev/s3       → { produce_images_bucket }
```

### How Pods Read Secrets

```
1. Pod starts in EKS
2. EKS injects IRSA credentials (AWS_ROLE_ARN, AWS_WEB_IDENTITY_TOKEN_FILE)
3. AWS SDK sees these env vars automatically
4. Pod calls: secretsManager.getSecretValue('agriconnect/dev/database')
5. IAM checks: does this pod's IRSA role have permission to read 'agriconnect/*'? YES
6. Secret returned as JSON string
7. Pod parses it and connects to MySQL
```

**Nobody ever sees the password in plain text** — not in the Docker image, not in environment variables, not in Kubernetes manifests, not in CI logs.

---

## 12. ECR — Where Your Docker Images Live

**What it is:** Elastic Container Registry. A private Docker image registry managed by AWS. Like Docker Hub but private and integrated with IAM.

**Your 5 repositories:**
```
893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-auth
893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-marketplace
893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-order
893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-media
893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-notification
```

### Image Lifecycle

**In CI (on every push to dev):**
```
Developer pushes code
→ GitHub Actions builds Docker image
→ Trivy scans image for vulnerabilities
→ Smoke test: runs container, hits /healthz
→ Pushes image to ECR with two tags:
    agriconnect-auth:b93b5a1  (git commit SHA — permanent)
    agriconnect-auth:latest   (always the newest)
```

**Lifecycle policy:** ECR is configured to keep only the last 10 images per repository. Older images are automatically deleted to save storage costs.

**When Kubernetes deploys:**
```
ArgoCD sees new image tag in Helm values
→ Kubernetes pulls image from ECR using the node's IAM role
   (AmazonEC2ContainerRegistryReadOnly is attached to node role)
→ Starts new pods with the new image
→ Health checks pass
→ Old pods are terminated
```

**scan_on_push = true:** ECR also scans images when pushed, in addition to the Trivy scan in CI. This gives you a second layer of vulnerability detection.

---

## 13. SNS — The Announcement System

**What it is:** Simple Notification Service. A publish/subscribe (pub/sub) message broker. You publish one message to a topic, and SNS delivers it to all subscribers simultaneously.

**Think of it as:** A public address system. You speak once into the microphone (publish). Everyone in the building hears it (subscribers).

### Your SNS Topics

**Topic 1: AgriConnect-Events**
```
Publisher:   order-service (when orders placed/updated)
             marketplace-service (when listings created)
Subscribers: SQS Queue (AgriConnect-Notifications-Queue)
```
When an order is placed, order-service publishes to this topic. The SQS queue receives it and notification-service processes it.

**Topic 2: AgriConnect-MonitoringAlerts**
```
Publisher:   CloudWatch Alarms (when RDS CPU high, EKS memory high, etc.)
Subscribers: Email (asadchamp109@gmail.com)
```
You get an email whenever any CloudWatch alarm fires.

**Topic 3: AgriConnect-WeatherAlerts**
```
Publisher:   Weather Alert Lambda (every 6 hours)
Subscribers: Notification service endpoint
```

**Topic 4: AgriConnect-FarmbotCritical**
```
Publisher:   FarmBot Lambda (when it detects a plant emergency)
Subscribers: Email (admin notification of critical crop issue)
```
When FarmBot's AI detects that a farmer's crops will be destroyed within 48 hours, it publishes to this topic. Admin gets alerted immediately.

### SNS → SQS Connection

SNS and SQS work together:
```
order-service → SNS (publish event)
                    ↓
                 SNS Topic (AgriConnect-Events)
                    ↓ fan-out
              SQS Queue (Notifications)
                    ↓
         notification-service polls and processes
```

This decouples the services. order-service doesn't know or care if notification-service is running. It just publishes the event. Even if notification-service is down, the message waits in SQS for up to 24 hours.

---

## 14. SQS — The Task Queue

**What it is:** Simple Queue Service. A message queue where messages wait until something processes them.

**Think of it as:** A ticket queue at a government office. Requests go in one end, someone processes them one at a time from the other end.

### Your SQS Setup

**Main Queue: AgriConnect-Notifications-Queue**
```
Visibility timeout: 30 seconds
  (once notification-service receives a message, SQS hides it from other
   processors for 30s. If not deleted in 30s, it reappears for retry.)

Message retention: 24 hours
  (if notification-service is down, messages wait up to 24 hours)

Max receive count: 3
  (if a message fails to process 3 times, move it to the DLQ)
```

**Dead Letter Queue: AgriConnect-Notifications-DLQ**
```
Retention: 14 days
Purpose: Stores messages that failed 3 processing attempts
```

If your notification service has a bug that causes it to crash on a specific message format, that message goes to the DLQ after 3 attempts instead of being lost. You can inspect the DLQ messages to debug the issue.

### How notification-service Processes Messages

```javascript
// Inside notification-service — runs forever
async function startSQSWorker() {
  while (true) {
    const { Messages } = await sqs.receiveMessage({
      QueueUrl: process.env.NOTIFICATIONS_QUEUE_URL,
      MaxNumberOfMessages: 10,
      WaitTimeSeconds: 20   // long polling — waits 20s for messages
    })

    for (const message of Messages || []) {
      const event = JSON.parse(message.Body)
      // e.g., { type: 'ORDER_PLACED', buyerId: 123, farmerId: 456 }

      await createNotificationInDB(event)
      // mark as read in the UI

      await sqs.deleteMessage({
        QueueUrl: QUEUE_URL,
        ReceiptHandle: message.ReceiptHandle
        // removes from queue so it's not processed again
      })
    }
  }
}
```

---

## 15. Lambda — Serverless Functions (Deep Dive)

**What it is:** Run code without managing servers. You upload a function, and AWS runs it when triggered. You pay only when the function actually executes (millisecond billing).

**Think of it as:** A vending machine. You press a button (trigger), the machine runs (function executes), gives you your snack (response), then goes idle again.

### Your 3 Lambda Functions

---

### Lambda 1: FarmBot Chatbot (Python)

**What it does:** AI agricultural advisor for farmers. Can answer questions and diagnose plant diseases from photos.

**Files:**
```
lambda/farmbot/
├── lambda_function.py  ← main handler (AWS calls this)
├── bedrock_client.py   ← wrapper for Amazon Bedrock AI
├── system_prompt.py    ← the AI's personality and rules
├── sns_handler.py      ← sends critical alerts
└── s3_handler.py       ← saves chat logs and photos
```

**How it works step by step:**

```
Farmer opens chat on website
  ↓
React frontend: POST /chat to API Gateway URL
  {
    "message": "My tomato leaves are turning yellow and falling off",
    "image": "base64encodedphoto...",  (optional)
    "conversation_history": [...],
    "farmer_id": "farmer123"
  }
  ↓
API Gateway receives request → triggers FarmBot Lambda
  ↓
lambda_function.py:
  1. Parses the event (message, image, history)
  2. If image present → calls s3_handler.store_photo() → saves to S3
  3. Builds the AI prompt using system_prompt.py
     "You are FarmBot, an agricultural advisor. Never discuss non-farm topics.
      Diagnose diseases with: WHAT I SEE, DIAGNOSIS, CAUSE, TREATMENT..."
  4. Calls bedrock_client.py with conversation history
  ↓
bedrock_client.py:
  Builds payload for Bedrock API:
  {
    "modelId": "amazon.nova-lite-v1:0",
    "messages": [
      {"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "data": "..."}},
        {"type": "text", "text": "My tomato leaves are yellowing"}
      ]}
    ],
    "inferenceConfig": {
      "maxTokens": 600,
      "temperature": 0.2,    ← low = consistent, factual answers
      "topP": 0.9
    }
  }
  ↓
Amazon Bedrock (Nova model) generates response:
  "WHAT I SEE: Yellow leaves with brown edges, wilting stems
   DIAGNOSIS: Early Blight (Alternaria solani)
   CAUSE: Fungal infection from soil splash
   TREATMENT: Remove affected leaves, apply copper-based fungicide
   CRITICAL: NO"
  ↓
lambda_function.py:
  5. Checks if CRITICAL flag is set
  6. If CRITICAL → sns_handler.py sends alert to SNS topic
     (admin notified, maybe farmer contacted by phone)
  7. Saves chat log to S3 for record keeping
  8. Returns response to API Gateway
  ↓
API Gateway → CloudFront → Browser → Farmer sees diagnosis
```

---

### Lambda 2: BuyerBot Chatbot (Python)

**What it does:** Marketplace assistant for buyers. Answers questions about listings, prices, bidding strategy.

**The interesting part — it reads LIVE data:**

```python
# inside tools.py

def search_listings(query, max_price=None):
    # calls YOUR OWN marketplace-service via the ALB
    response = requests.get(
        f"{ALB_URL}/api/marketplace/listings",
        params={"search": query, "maxPrice": max_price}
    )
    return response.json()
```

**Flow:**
```
Buyer asks: "How much are organic tomatoes right now?"
  ↓
BuyerBot Lambda starts
  ↓
Lambda calls marketplace-service via ALB → gets live listings
{
  listings: [
    { name: "Organic Tomatoes", price: 45, farm: "Green Valley Farm", location: "Pune" },
    { name: "Organic Tomatoes", price: 38, farm: "Sunrise Farm", location: "Nashik" }
  ]
}
  ↓
Lambda builds Bedrock prompt:
  "You are BuyerBot. Here are current listings: [live data]
   Answer buyer questions based on this real data."
  ↓
Bedrock generates: "Organic tomatoes are currently listed between ₹38-45/kg.
   The cheapest is Sunrise Farm in Nashik at ₹38/kg."
  ↓
Buyer gets accurate, real-time information
```

**Why not query the DB directly from Lambda?**
Lambda is outside your VPC (serverless). It can't reach RDS in the private subnet. Instead, it calls your marketplace-service via the ALB (which IS publicly accessible). The service handles the DB query and returns JSON.

---

### Lambda 3: Weather Alert Processor (Node.js)

**What it does:** Every 6 hours, sends weather-related agricultural advice to farmers as notifications.

**The code:**
```javascript
// index.js
const messages = [
  { type: 'RAIN_ALERT',  message: 'Heavy rain expected. Delay pesticide application...' },
  { type: 'HEAT_ALERT',  message: 'Temperature above 40°C. Increase irrigation...' },
  { type: 'STORM_ALERT', message: 'Strong winds expected. Secure young plants...' },
  { type: 'DRY_ALERT',   message: 'Dry spell continuing. Monitor soil moisture...' }
]

// Rotates messages based on the hour
const messageIndex = Math.floor(new Date().getUTCHours() / 6) % messages.length
const alert = messages[messageIndex]

// Calls notification-service via ALB
await fetch(`${ALB_URL}/api/notifications/broadcast`, {
  method: 'POST',
  body: JSON.stringify(alert)
})
```

**Triggered by:** EventBridge Scheduler every 6 hours. Automatically, no human involved.

---

### How Lambda Code Gets Deployed — The ZIP Story

This is the exact flow of how your Python/JavaScript code gets into Lambda:

**For FarmBot and BuyerBot (Python — packaged differently):**

Terraform uses the `archive_file` data source:
```hcl
data "archive_file" "farmbot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/farmbot/"  # entire folder
  output_path = "${path.module}/farmbot_package.zip"
}
```

When you run `terraform plan` or `terraform apply`:
1. Terraform reads all files in `lambda/farmbot/`
2. Zips them into `farmbot_package.zip`
3. Calculates SHA256 hash of the zip
4. Compares hash with last deploy's hash (stored in state)
5. If hash changed → upload new zip to Lambda
6. If hash unchanged → skip (no redeployment needed)

```hcl
resource "aws_lambda_function" "farmbot_chatbot" {
  filename         = data.archive_file.farmbot.output_path      # local zip
  function_name    = "farmbot-chatbot"
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"           # file.function
  role             = module.security.lambda_role_arn
  timeout          = 30
  source_code_hash = data.archive_file.farmbot.output_base64sha256  # triggers update
}
```

**The `handler` field:** `lambda_function.lambda_handler` means:
- File: `lambda_function.py`
- Function: `def lambda_handler(event, context):`

AWS Lambda calls this exact function when triggered.

**For Weather Alert (Node.js — single file):**
```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "../lambda/weather-alert-processor/index.js"  # single file
  output_path = "${path.module}/lambda_package.zip"
}
```

**Handler:** `index.handler` = file `index.js`, function `exports.handler`

**Environment variables injected by Terraform:**
```hcl
environment {
  variables = {
    BEDROCK_REGION = "ap-south-1"
    MODEL_ID       = "amazon.nova-lite-v1:0"
    S3_BUCKET_NAME = var.s3_produce_images_bucket
    SNS_TOPIC_ARN  = aws_sns_topic.farmbot_critical.arn
    MAX_IMAGE_SIZE_MB = "5"
  }
}
```

Lambda reads these like normal environment variables in the code:
```python
import os
sns_topic = os.environ['SNS_TOPIC_ARN']
```

---

## 16. API Gateway — Lambda's Front Door

**What it is:** A fully managed API service that sits in front of your Lambda functions. It receives HTTP requests, passes them to Lambda, and returns Lambda's response back.

**Why Lambda needs API Gateway:**
Lambda functions can't receive HTTP requests directly. They're triggered by events. API Gateway converts an HTTP request into a Lambda event.

### Your Two API Gateways

```
POST https://abc123.execute-api.ap-south-1.amazonaws.com/prod/chat
                    ↓
          API Gateway (FarmBot)
                    ↓
          Lambda: farmbot-chatbot
                    ↓
          Returns: { reply: "...", critical: false }
                    ↓
          API Gateway returns HTTP 200 with JSON body
```

**HTTP API vs REST API:**
You're using HTTP API (newer, cheaper, faster) not REST API (older, more features). HTTP API is 71% cheaper for simple proxy use cases like this.

### CORS on API Gateway
```hcl
cors_configuration {
  allow_origins = ["*"]
  allow_methods = ["POST", "OPTIONS"]
  allow_headers = ["Content-Type"]
}
```

The browser makes an OPTIONS "preflight" request before the actual POST. CORS configuration tells the browser: "yes, this API accepts requests from any origin."

### The Event Object Lambda Receives
```json
{
  "version": "2.0",
  "routeKey": "POST /chat",
  "requestContext": { "http": { "method": "POST" } },
  "body": "{\"message\": \"how do I grow tomatoes?\", \"farmer_id\": \"f123\"}",
  "isBase64Encoded": false
}
```

Lambda parses `event['body']` to get the actual request data.

### API URL → SSM → Frontend
After Terraform creates API Gateway:
```hcl
resource "aws_ssm_parameter" "farmbot_api_url" {
  name  = "/agriconnect/farmbot_api_url"
  value = "${aws_apigatewayv2_stage.farmbot.invoke_url}/chat"
  # → "https://abc123.execute-api.ap-south-1.amazonaws.com/prod/chat"
}
```

When frontend builds in CI:
```bash
FARMBOT_URL=$(aws ssm get-parameter --name /agriconnect/farmbot_api_url --query Parameter.Value --output text)
VITE_FARMBOT_API_URL=$FARMBOT_URL npm run build
```

The URL gets baked into the React bundle at build time.

---

## 17. Amazon Bedrock — The AI Brain

**What it is:** AWS's managed AI service. It gives you access to foundation models (large language models) via an API. You don't host the model — AWS runs it, you just call the API.

**Your model:** `amazon.nova-lite-v1:0`
- Nova Lite: Fast, cost-efficient model for conversational AI
- Supports text + images (multimodal)

### How FarmBot Calls Bedrock

```python
# bedrock_client.py
import boto3

client = boto3.client('bedrock-runtime', region_name='ap-south-1')

payload = {
    "modelId": "amazon.nova-lite-v1:0",
    "messages": conversation_history + [
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "mediaType": "image/jpeg",
                        "data": base64_image
                    }
                },
                {
                    "type": "text",
                    "text": "My tomato plants look sick"
                }
            ]
        }
    ],
    "system": [{"text": SYSTEM_PROMPT}],  # FarmBot's personality
    "inferenceConfig": {
        "maxTokens": 600,
        "temperature": 0.2,   # 0 = deterministic, 1 = creative
        "topP": 0.9
    }
}

response = client.invoke_model(**payload)
result = json.loads(response['body'].read())
reply = result['output']['message']['content'][0]['text']
```

**Temperature 0.2:** Low temperature means the model gives consistent, factual answers rather than creative ones. For a medical/agricultural advisor, you want reliable answers, not creative fiction.

**Conversation history (last 20 messages):** Bedrock is stateless — it doesn't remember previous messages. The Lambda function sends the entire conversation history with every request:
```json
[
  {"role": "user",      "content": "My tomatoes are yellowing"},
  {"role": "assistant", "content": "This looks like early blight..."},
  {"role": "user",      "content": "What treatment should I use?"}
]
```

---

## 18. EventBridge — The Cron Job Scheduler

**What it is:** AWS's event bus and scheduling service. It can trigger Lambda functions on a schedule — like a cron job, but fully managed.

**Your schedule:**
```hcl
resource "aws_scheduler_schedule" "weather_check" {
  name                = "weather-alert-check"
  schedule_expression = "rate(6 hours)"   # every 6 hours
  schedule_expression_timezone = "Asia/Kolkata"

  target {
    arn   = aws_lambda_function.weather_alert.arn
    input = jsonencode({ source = "scheduler" })
  }
}
```

**Every 6 hours, AWS automatically:**
1. Creates an event: `{ "source": "scheduler" }`
2. Sends it to the weather-alert-processor Lambda
3. Lambda wakes up, selects the right weather message, calls notification-service
4. Farmers receive a weather advisory notification
5. Lambda finishes, goes back to sleep

**No EC2 instance running 24/7.** Lambda only runs for the ~2 seconds it takes to process. You pay for those 2 seconds every 6 hours — essentially free under the AWS free tier.

**EventBridge vs CloudWatch Events:** EventBridge Scheduler is the newer service with timezone support and higher scheduling precision. CloudWatch Events (now called EventBridge rules) was the older approach. Same concept, newer service.

---

## 19. CloudWatch — Monitoring and Alerts

**What it is:** AWS's monitoring and observability service. Collects logs, metrics, and triggers alerts.

### CloudWatch Log Groups

Every Lambda function and EKS pod writes logs to CloudWatch:

```
/aws/containerinsights/agriconnect-dev-eks/application  ← EKS pod logs
/aws/containerinsights/agriconnect-dev-eks/dataplane    ← Kubernetes system logs
/aws/lambda/weather-alert-processor                     ← weather Lambda logs
/aws/lambda/farmbot-chatbot                             ← FarmBot Lambda logs
/aws/lambda/buyerbot-chatbot                            ← BuyerBot Lambda logs
```

**30-day retention:** Logs older than 30 days are automatically deleted. Without this, logs accumulate forever and cost money.

**How to read logs:**
```bash
# See FarmBot logs in real time
aws logs tail /aws/lambda/farmbot-chatbot --follow

# Search for errors in the last hour
aws logs filter-log-events \
  --log-group-name /aws/lambda/farmbot-chatbot \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000)
```

### CloudWatch Alarms — Your 5 Watchers

**Alarm 1: RDS CPU High**
```
Metric:    CPUUtilization on your MySQL RDS instance
Threshold: > 80% for 2 consecutive 5-minute periods (10 minutes total)
Action:    Publish to MonitoringAlerts SNS → email you
Why:       RDS CPU spike = queries are slow or connection pool is saturated
```

**Alarm 2: RDS Storage Low**
```
Metric:    FreeStorageSpace on RDS
Threshold: < 2 GB
Action:    Email alert
Why:       If disk fills up, MySQL stops accepting writes — application breaks
```

**Alarm 3: EKS Node CPU High**
```
Metric:    node_cpu_utilization (Container Insights metric)
Threshold: > 85% for 10 minutes
Action:    Email alert
Why:       Nodes at 85% CPU means pods are throttled, responses are slow
           → time to add more nodes (increase node desired size)
```

**Alarm 4: EKS Node Memory High**
```
Metric:    node_memory_utilization
Threshold: > 85%
Action:    Email alert
Why:       Memory pressure causes Kubernetes to evict pods, causing crashes
```

**Alarm 5: Pod Restart Count**
```
Metric:    pod_number_of_container_restarts
Threshold: > 1 restart in 5 minutes
Action:    Email alert
Why:       Pods shouldn't restart. If they do, it means crashes (OOM, app error)
```

### Container Insights

The EKS cluster has the **Container Insights addon** installed. This agent runs on every node and collects:
- Per-pod CPU and memory usage
- Node-level metrics
- Network I/O
- Disk I/O

These metrics appear in CloudWatch under the `ContainerInsights` namespace and feed the alarms above.

---

## 20. SSM Parameter Store — Configuration Registry

**What it is:** AWS Systems Manager Parameter Store. A configuration registry where you store non-secret configuration values that multiple systems need to read.

**Think of it as:** A shared `.env` file in the cloud that any authorized AWS service can read.

### Your SSM Parameters

```
/agriconnect/farmbot-api-url      → "https://abc.execute-api.../prod/chat"
/agriconnect/buyerbot-api-url     → "https://xyz.execute-api.../prod/chat"
/agriconnect/cloudfront-distribution-id → "EABC123..."
/agriconnect/eks-cluster-name     → "agriconnect-dev-eks"
/agriconnect/eks-services-irsa-role-arn → "arn:aws:iam::..."
/agriconnect/public-subnet-ids    → "subnet-abc,subnet-xyz"
```

### How SSM Parameters Flow Through Your System

```
Step 1: terraform apply creates API Gateway
         → Lambda URL generated: https://abc123.execute-api.ap-south-1.amazonaws.com/prod/chat
         → Terraform writes it to SSM: /agriconnect/farmbot-api-url

Step 2: CI pipeline builds the React frontend
         → cd-frontend.yml:
           FARMBOT_URL=$(aws ssm get-parameter \
             --name /agriconnect/farmbot_api_url \
             --with-decryption --query Parameter.Value --output text)
           VITE_FARMBOT_API_URL=$FARMBOT_URL npm run build
         → React bundle compiled with the real API URL baked in

Step 3: Frontend deployed to S3
         → Users download index.js which contains the hardcoded API URL
         → React app sends chatbot requests to the correct Lambda URL
```

**Without SSM:** You'd hardcode the API URL in the frontend code. Every time Terraform recreates API Gateway (different URL), you'd have to manually update the frontend code.

---

## 21. IRSA — How Pods Access AWS Without Passwords

**What it is:** IAM Roles for Service Accounts. The mechanism that lets Kubernetes pods securely call AWS APIs without any stored credentials.

### The Problem

Your auth-service pod needs to:
- Read DB password from Secrets Manager
- Upload images to S3
- Publish events to SNS
- Send messages to SQS

How does it authenticate to AWS? Options:

| Option | Problem |
|---|---|
| Hardcode access keys in Docker image | Keys leak if image is inspected |
| Pass keys as env variables | Visible in `kubectl describe pod`, pod spec in Git |
| Use the EC2 node's IAM role | ALL pods on the node share the same role — too permissive |
| **IRSA** | Each pod gets its own temporary AWS identity ✅ |

### How IRSA Works (Step by Step)

```
1. EKS creates an OIDC provider
   (an identity provider that issues signed JWT tokens to pods)

2. In Terraform, you create an IAM role with a trust policy:
   "Only allow this specific Kubernetes ServiceAccount in the production
    namespace of THIS cluster to assume this role"

3. In Helm, ServiceAccount manifest has annotation:
   eks.amazonaws.com/role-arn: arn:aws:iam::893431614084:role/agriconnect-dev-eks-services-role

4. When a pod starts (using this ServiceAccount):
   EKS mutating webhook injects two env vars into the pod:
   AWS_ROLE_ARN = arn:aws:iam::893431614084:role/agriconnect-dev-eks-services-role
   AWS_WEB_IDENTITY_TOKEN_FILE = /var/run/secrets/eks.amazonaws.com/serviceaccount/token

5. When the pod calls AWS SDK (e.g., secretsManager.getSecretValue):
   SDK reads AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE automatically
   SDK calls STS: "I have this signed JWT from EKS, I want to assume this role"
   STS verifies: JWT signed by EKS OIDC? ✓  ServiceAccount matches? ✓  Namespace matches? ✓
   STS issues temporary credentials (15-minute tokens, auto-renewed)
   SDK uses these temporary credentials for the API call

6. The IAM role only has specific permissions:
   - secretsmanager:GetSecretValue on "agriconnect/*"
   - sns:Publish
   - sqs:SendMessage, ReceiveMessage, DeleteMessage
   - s3:GetObject, PutObject, DeleteObject on "agriconnect-*" buckets
```

**The result:** No password, no access key, no secret anywhere in the pod or its manifest. The identity is cryptographically tied to the exact pod, namespace, and cluster.

---

## 22. NAT Gateway — Private Subnet Internet Access

**What it is:** Network Address Translation Gateway. Lets resources in private subnets reach the internet without being reachable from the internet.

**Why your EKS nodes need it:**
- Pull Docker images from ECR (requires HTTPS to AWS APIs)
- Call Secrets Manager API (requires HTTPS to AWS endpoint)
- Download OS updates, install packages
- Call external services (weather API, etc.)

**How it works:**
```
EKS node (10.0.10.5) wants to reach ECR (54.240.x.x)
  ↓
Private subnet route table: 0.0.0.0/0 → NAT Gateway
  ↓
NAT Gateway (in public subnet, has Elastic IP: 13.233.x.x)
  ↓
Traffic leaves AWS to the internet as 13.233.x.x
  ↓
ECR responds to 13.233.x.x
  ↓
NAT Gateway translates back to 10.0.10.5
  ↓
EKS node receives the Docker image
```

**Cost:** ~$33/month for the gateway + $0.045/GB of data transferred. This is the second biggest cost item after EKS nodes.

**Optimization opportunity:** For S3 and SQS, you can use **VPC Endpoints** — private connections that bypass NAT entirely. Data from private subnets to S3/SQS flows inside AWS's private network, not through NAT. The `cost_estimation` Terraform output mentions this.

---

## 23. How the Frontend Gets Deployed to S3

This is the complete flow when a developer pushes frontend code:

```
Developer pushes to dev branch
  ↓
GitHub Actions: main.yml triggers
  ↓
changes job: detects frontend/** files changed → yes
  ↓
After all service builds pass
  ↓
cd-frontend.yml runs:

  Step 1: Configure AWS credentials (from GitHub Secrets)
  
  Step 2: Set up Node.js 22
  
  Step 3: Read API URLs from SSM
    FARMBOT_URL=$(aws ssm get-parameter \
      --name /agriconnect/farmbot_api_url --query Parameter.Value)
    BUYERBOT_URL=$(aws ssm get-parameter \
      --name /agriconnect/buyerbot_api_url --query Parameter.Value)
  
  Step 4: Install dependencies
    cd frontend && npm install
  
  Step 5: Build React app with real API URLs
    VITE_FARMBOT_API_URL=$FARMBOT_URL \
    VITE_BUYERBOT_API_URL=$BUYERBOT_URL \
    npm run build
    → produces dist/ folder
  
  Step 6: Upload to S3
    aws s3 sync dist/ s3://agriconnect-frontend-893431614084/ \
      --delete \      ← removes files that no longer exist
      --cache-control max-age=31536000  ← assets cached 1 year
  
  Step 7: Invalidate CloudFront cache
    aws cloudfront create-invalidation \
      --distribution-id $CLOUDFRONT_ID \
      --paths "/*"
    ← CloudFront was serving old cached files
    ← Invalidation forces it to fetch fresh files from S3
    ← Takes 30-60 seconds to propagate globally
```

**After this:**
1. Users in Mumbai see the new frontend immediately (cached at Mumbai edge)
2. Users in Delhi see it within 60 seconds (CloudFront invalidation propagates)
3. The API URLs are baked into the JavaScript bundle — correct environment, correct Lambda URLs

---

## 24. How Lambda Code Gets Deployed (The ZIP Story)

This is the exact journey of your Python/Node.js code from your laptop to running in AWS Lambda.

### For FarmBot and BuyerBot (Python)

```
Your code lives in:
stage-infra/lambda/farmbot/
├── lambda_function.py
├── bedrock_client.py
├── system_prompt.py
├── sns_handler.py
└── s3_handler.py
```

**Step 1: You push to main branch**
The infra-terraform.yml pipeline triggers.

**Step 2: terraform plan runs**
```hcl
data "archive_file" "farmbot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/farmbot/"
  output_path = "${path.module}/farmbot_package.zip"
}
```
Terraform zips the entire `lambda/farmbot/` directory into `farmbot_package.zip`.
It also calculates: `sha256(farmbot_package.zip)` = `"abc123..."`

**Step 3: Terraform compares with last deploy**
In the state file, it has: `previous_hash = "xyz789..."`
New hash `"abc123..."` ≠ previous `"xyz789..."` → code changed → update Lambda.

**Step 4: After manual approval, terraform apply runs**
```hcl
resource "aws_lambda_function" "farmbot_chatbot" {
  filename         = "farmbot_package.zip"        # ← local zip file
  function_name    = "farmbot-chatbot"
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"
  source_code_hash = "abc123..."
}
```
Terraform calls AWS API: `UpdateFunctionCode(ZipFile=farmbot_package.zip)`
AWS uploads the zip, extracts it inside Lambda's execution environment.

**Step 5: Lambda is ready**
When API Gateway calls the Lambda:
```python
# AWS calls this function
def lambda_handler(event, context):
    body = json.loads(event['body'])
    message = body['message']
    # ... process and return response
```

**For Weather Alert (Node.js — CI pipeline zips it)**
```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/weather-alert-processor/index.js"
  output_path = "${path.module}/lambda_package.zip"
}
```
Same process — Terraform zips `index.js`, uploads to Lambda on change.

### Lambda Execution Environment

When Lambda runs:
```
AWS spins up a micro container (100ms cold start)
→ Python 3.12 runtime initialized
→ Your code loaded from the zip
→ lambda_handler(event, context) called
→ Code runs (up to 30 seconds timeout for FarmBot)
→ Returns response
→ Container stays warm for ~15 minutes (handles next request instantly)
→ If idle > 15 minutes, container destroyed (next request = cold start again)
```

---

## 25. Complete End-to-End Flows

### Flow 1: Farmer Lists Produce

```
1. Farmer fills out "New Listing" form in React
2. React: POST /api/marketplace/listings
   { crop: "Tomatoes", quantity: 100, price: 45, unit: "kg" }
   
3. Request goes: Browser → CloudFront → ALB → marketplace-service pod

4. marketplace-service:
   - Validates JWT token (calls auth-service internally)
   - Creates listing in RDS
   - Publishes SNS event: { type: "LISTING_CREATED", listingId: 789 }
   
5. SNS → SQS → notification-service picks up the message
6. notification-service creates notification records in RDS for subscribed buyers
7. Buyers see "New Tomato listing from Green Valley Farm" notification
```

### Flow 2: Farmer Asks FarmBot About Disease

```
1. Farmer uploads photo of sick plant, types "what's wrong with my tomato?"
2. React: POST https://abc.execute-api.ap-south-1.amazonaws.com/prod/chat
   { message: "...", image: "base64...", farmer_id: "f123", history: [...] }
   
3. API Gateway → FarmBot Lambda (Python wakes up)

4. Lambda:
   - Stores photo in S3: /photos/f123/2024-01-15T10:30.jpg
   - Calls bedrock_client.py with conversation history + image
   
5. Bedrock Nova Lite analyzes the photo + text → generates diagnosis

6. Lambda:
   - Checks CRITICAL flag in response
   - Saves chat log to S3: /chatlogs/f123/2024-01-15T10:30.json
   - If CRITICAL → sns_handler.py → SNS FarmbotCritical topic → admin gets email
   
7. Lambda returns: { reply: "Early Blight detected...", critical: false }
8. API Gateway → CloudFront → Browser → Farmer reads diagnosis
```

### Flow 3: Buyer Uses BuyerBot to Find Listings

```
1. Buyer types: "find me organic tomatoes under ₹50/kg"
2. React: POST to BuyerBot API Gateway URL

3. BuyerBot Lambda starts:
   - Parses the message
   - Calls tools.py: search_listings(query="organic tomatoes", max_price=50)
   - tools.py calls: GET http://ALB-DNS/api/marketplace/listings?search=...
   - Gets live listings from marketplace-service → from RDS
   
4. Lambda builds Bedrock prompt:
   "Current organic tomato listings: [list of 8 real listings]"
   
5. Bedrock generates: "I found 3 organic tomato listings under ₹50/kg:
   - Sunrise Farm, Nashik: ₹38/kg (50 kg available)
   - Green Valley, Pune: ₹45/kg (200 kg available)..."
   
6. Buyer gets accurate, real-time answer based on live marketplace data
```

### Flow 4: Weather Alert Every 6 Hours

```
1. EventBridge fires at 06:00, 12:00, 18:00, 00:00 IST

2. EventBridge sends event to weather-alert Lambda:
   { "source": "scheduler" }

3. Lambda wakes up:
   - Checks current UTC hour → selects appropriate weather message
   - POST to http://ALB-DNS/api/notifications/broadcast
   { type: "HEAT_ALERT", message: "Temperature above 40°C..." }
   
4. notification-service receives broadcast request
   → creates notifications for all registered farmers
   → farmers see weather alerts in their notification bell
   
5. Lambda finishes, goes back to sleep until next 6-hour interval
```

### Flow 5: Order Placed and Notification Sent

```
1. Buyer clicks "Place Order" for 50 kg of tomatoes
2. React: POST /api/orders
   { listingId: 789, quantity: 50, buyerId: 456 }

3. order-service pod:
   - Validates the request
   - Creates order record in RDS
   - Publishes to SNS: { type: "ORDER_PLACED", orderId: 101, farmerId: 123, buyerId: 456 }

4. SNS → SQS (AgriConnect-Notifications-Queue)

5. notification-service SQS worker picks up message:
   - Creates notification: { userId: 123, message: "New order for your tomatoes!" }
   - Creates notification: { userId: 456, message: "Your order was placed!" }
   - Saves to RDS
   - Deletes message from SQS

6. Farmer and Buyer see notifications in their notification bell in the React app
```

### Flow 6: CI/CD — New Code Goes Live

```
Developer pushes auth-service code fix to dev branch
  ↓
main.yml pipeline starts:
  
  Phase 1: Security (parallel)
  ├── SonarCloud scans all JS code for vulnerabilities
  └── Snyk checks all npm dependencies for CVEs

  Phase 2: Lint (after Phase 1)
  └── ESLint checks all service code for errors

  Phase 3: Build all 5 services (parallel, after lint)
  ├── ci-auth.yml:
  │   ├── docker build (multistage, Node.js Alpine)
  │   ├── trivy scan (fails if CRITICAL CVE found)
  │   ├── smoke test: docker run → curl /healthz → must return 200
  │   └── docker push to ECR: agriconnect-auth:b93b5a1
  ├── ci-marketplace.yml (same steps)
  ├── ci-order.yml (same steps)
  ├── ci-media.yml (same steps)
  └── ci-notification.yml (same steps)

  Phase 4: Update Helm (after all 5 build jobs pass)
  └── update-helm-values:
      ├── checkout agriconnect-helm repo
      ├── update values.yaml: tag: b93b5a1
      └── push to agriconnect-helm dev branch

  Phase 5: ArgoCD (automatic, ~2 minutes later)
  └── ArgoCD detects values.yaml changed
      └── kubectl set image deployment/auth agriconnect-auth:b93b5a1
          └── Rolling update: new pod starts → health check passes → old pod killed
```

---

## Service Summary Table

| Service | What it does in AgriConnect | Where |
|---|---|---|
| CloudFront | Serves the React app globally, routes /api to ALB | Edge (global) |
| WAF | Blocks SQLi, XSS, brute force before CloudFront | us-east-1 |
| S3 (frontend) | Hosts compiled React app files | ap-south-1 |
| S3 (images) | Stores farmer produce photos | ap-south-1 |
| ALB | Routes /api/* to correct microservice pod | Public subnet |
| EKS | Runs all 5 Node.js microservices | Private subnet |
| RDS MySQL | Stores users, listings, orders, bids | Private subnet |
| Secrets Manager | Stores DB password, JWT secret, SMTP | ap-south-1 |
| ECR | Stores Docker images for all 5 services | ap-south-1 |
| SNS | Event bus — order events, weather alerts, emergencies | ap-south-1 |
| SQS | Queue for notifications, dead letter queue | ap-south-1 |
| FarmBot Lambda | AI advisor for farmers (Bedrock) | ap-south-1 |
| BuyerBot Lambda | AI marketplace assistant for buyers | ap-south-1 |
| Weather Lambda | Sends weather alerts every 6 hours | ap-south-1 |
| API Gateway | HTTP endpoint for FarmBot and BuyerBot | ap-south-1 |
| Bedrock | Foundation model (Nova Lite) for AI responses | ap-south-1 |
| EventBridge | Triggers weather Lambda every 6 hours | ap-south-1 |
| CloudWatch | Logs, 5 alarms, Container Insights | ap-south-1 |
| SSM Parameter Store | Stores API URLs for CI/CD to read | ap-south-1 |
| IRSA | Pods get temporary AWS credentials securely | EKS-native |
| NAT Gateway | Private pods reach internet (ECR, AWS APIs) | Public subnet |
| VPC | Isolated network, subnets, routing | ap-south-1 |

---

*Every service listed here is actively used by your application. Nothing is decorative.*
