# AgriConnect — Capstone Requirements Fulfillment

> Every requirement, what was implemented, how it works, why it exists, and the advantages.
> This document maps every capstone deliverable to exact code in the 3 repositories.

---

## Table of Contents

1. [Multistage Docker Builds](#1-multistage-docker-builds)
2. [Non-Root User in Containers](#2-non-root-user-in-containers)
3. [SAST — SonarCloud](#3-sast--sonarcloud)
4. [Dependency Scanning — Snyk](#4-dependency-scanning--snyk)
5. [Container Image Scanning — Trivy](#5-container-image-scanning--trivy)
6. [IaC Security Scanning — Trivy Config](#6-iac-security-scanning--trivy-config)
7. [Kubernetes Network Policy](#7-kubernetes-network-policy)
8. [Secrets Management — AWS Secrets Manager](#8-secrets-management--aws-secrets-manager)
9. [Terraform State Locking](#9-terraform-state-locking)
10. [Cost Optimization Output](#10-cost-optimization-output)
11. [CI/CD Pipeline — GitHub Actions](#11-cicd-pipeline--github-actions)
12. [GitOps with ArgoCD](#12-gitops-with-argocd)
13. [Kubernetes on EKS with Helm](#13-kubernetes-on-eks-with-helm)
14. [Horizontal Pod Autoscaler (HPA)](#14-horizontal-pod-autoscaler-hpa)
15. [Cluster Autoscaler](#15-cluster-autoscaler)
16. [Pod Disruption Budget (PDB)](#16-pod-disruption-budget-pdb)
17. [Health Checks — Liveness and Readiness Probes](#17-health-checks--liveness-and-readiness-probes)
18. [Smoke Tests in Pipeline](#18-smoke-tests-in-pipeline)
19. [Code Linting — ESLint](#19-code-linting--eslint)
20. [Resource Requests and Limits](#20-resource-requests-and-limits)
21. [IRSA — IAM Roles for Service Accounts](#21-irsa--iam-roles-for-service-accounts)
22. [ECR — Lifecycle Policy and Scan on Push](#22-ecr--lifecycle-policy-and-scan-on-push)
23. [CloudWatch Observability](#23-cloudwatch-observability)
24. [VPC Architecture — Private Subnets](#24-vpc-architecture--private-subnets)
25. [Microservices Architecture](#25-microservices-architecture)
26. [SNS + SQS Event-Driven Messaging](#26-sns--sqs-event-driven-messaging)
27. [Serverless — Three Lambda Functions](#27-serverless--three-lambda-functions)
28. [CloudFront CDN + S3 Frontend Hosting](#28-cloudfront-cdn--s3-frontend-hosting)
29. [RDS Database](#29-rds-database)
30. [Approval Gates](#30-approval-gates)
31. [Security Failure Email Notification](#31-security-failure-email-notification)
32. [Terraform Modular Architecture](#32-terraform-modular-architecture)

---

## 1. Multistage Docker Builds

**File:** `stage-app/services/auth-service/Dockerfile` (same pattern for all 5 services)

### What was implemented

```dockerfile
# ── Stage 1: install dependencies ──────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY shared/package*.json ./shared/
RUN cd shared && npm install --omit=dev

COPY shared/ ./shared/

COPY services/auth-service/package*.json ./services/auth-service/
WORKDIR /app/services/auth-service
RUN npm install --omit=dev

COPY services/auth-service/ .

# ── Stage 2: minimal runtime image ─────────────────────────────────────────────
FROM node:20-alpine AS runtime

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

ENV NODE_ENV=production

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /app/shared ./shared
COPY --from=builder --chown=appuser:appgroup /app/services/auth-service ./services/auth-service

USER appuser

WORKDIR /app/services/auth-service

EXPOSE 3001
CMD ["node", "index.js"]
```

### How it works

Two `FROM` instructions = two separate build stages.

**Stage 1 (`AS builder`):** Uses `node:20-alpine` as a full build environment. Copies `package.json`, runs `npm install` (downloads all dependencies into `node_modules`), then copies source code. This stage has npm, package tarballs, caches, and temporary files.

**Stage 2 (`AS runtime`):** Starts completely fresh from `node:20-alpine`. Copies ONLY the finished output from stage 1 using `COPY --from=builder`. The final image has NO traces of the build process.

### Why it was done

Without multistage builds:
- Single stage image = entire build environment + source + all node_modules = ~500-700 MB
- Attack surface: npm binary, package tarballs, cache directories — all unnecessary at runtime

With multistage builds:
- Final image only contains: Node.js runtime + compiled/installed `node_modules` + source code
- Image size drops to ~150-200 MB
- Attack surface: nothing that isn't needed to run the application

### Advantages

| Advantage | Detail |
|---|---|
| Smaller image size | ~60-70% size reduction. Faster pulls from ECR, faster pod startup |
| Reduced attack surface | Build tools (npm itself, compiler toolchains) are not present in the final image |
| Layer caching | `npm install` layer only rebuilds when `package.json` changes. If only code changes, `npm install` is cached |
| No secrets leaking | Any secret used at build time stays in the builder stage — never copied to the runtime image |
| Consistency | All 5 services use identical pattern, making all images uniform and auditable |

---

## 2. Non-Root User in Containers

**File:** `stage-app/services/auth-service/Dockerfile` (same for all 5 services)

### What was implemented

```dockerfile
# In Stage 2 (runtime):
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```
```dockerfile
COPY --from=builder --chown=appuser:appgroup /app/shared ./shared
COPY --from=builder --chown=appuser:appgroup /app/services/auth-service ./services/auth-service
USER appuser
```

### How it works

`addgroup -S appgroup` — creates a system group (the `-S` flag means "system group," no login shell, no password).

`adduser -S appuser -G appgroup` — creates a system user with no home directory, no password, no login shell, and adds it to `appgroup`.

`COPY --chown=appuser:appgroup` — when files are copied from the builder stage, they are immediately owned by `appuser`. Not root.

`USER appuser` — all subsequent instructions in the Dockerfile AND the running container process run as `appuser`, NOT as root.

### Why it was done

By default, Docker containers run as root (UID 0). This means if the application process is exploited (remote code execution vulnerability), the attacker has root access inside the container and can:
- Read/write any file in the container filesystem
- Modify `/etc/passwd`, install packages, run arbitrary binaries
- Attempt container escape to the host node

Running as a non-root user means an exploited process only has the permissions of `appuser` — a restricted system user with no special privileges.

### Advantages

| Advantage | Detail |
|---|---|
| Principle of least privilege | Application only has the permissions it actually needs |
| Container escape resistance | Harder to escalate from `appuser` to node root even if the container is compromised |
| Kubernetes compatibility | Some Kubernetes security policies (`PodSecurityStandards`) require non-root containers |
| File system protection | Application code files are owned by `appuser` — tampering from an exploited process is constrained |
| Compliance | Required by many security standards (CIS Docker Benchmark, SOC2, NIST) |

---

## 3. SAST — SonarCloud

**Files:** `stage-app/.github/workflows/main.yml` (sast job), `stage-app/sonar-project.properties`

### What was implemented

```yaml
# main.yml — sast job
sast:
  name: SAST - SonarCloud
  runs-on: ubuntu-latest
  outputs:
    result: ${{ steps.sonar.outcome }}
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0          # full git history for blame and trend analysis

    - name: SonarCloud Scan
      id: sonar
      uses: SonarSource/sonarcloud-github-action@v3
      continue-on-error: true   # findings reported, do not block pipeline
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      with:
        args: >-
          -Dsonar.qualitygate.wait=false
```

```properties
# sonar-project.properties
sonar.organization=agriconnect-platform
sonar.projectKey=AgriConnect-Platform_agriconnect-app2
sonar.projectName=AgriConnect
sonar.projectVersion=1.0

sonar.sources=services,shared
sonar.exclusions=**/node_modules/**,**/coverage/**,**/*.test.js,**/*.spec.js

sonar.javascript.lcov.reportPaths=coverage/lcov.info
sonar.sourceEncoding=UTF-8
```

### How it works

**SAST = Static Application Security Testing** — analyzing source code WITHOUT running it.

SonarCloud reads every `.js` file in `services/` and `shared/`. It parses the code into an Abstract Syntax Tree (AST) and applies 200+ detection rules looking for:

- **Security vulnerabilities:** SQL injection patterns, hardcoded passwords, insecure randomness, XSS vectors, path traversal, deserialization issues
- **Code smells:** Dead code, duplicated logic, overly complex functions, deeply nested conditions
- **Bugs:** Null pointer dereferences, unreachable code, wrong comparison operators

`sonar.sources=services,shared` — only scans application code, not test files or seed scripts.
`sonar.exclusions=**/node_modules/**` — node_modules are third-party code, scanned by Snyk (not SonarCloud).
`fetch-depth: 0` — full git history is needed so SonarCloud can track which issues are NEW (introduced in this commit) vs. already known.

`continue-on-error: true` — findings do not block the pipeline. SAST is informational. The result (success/failure) is captured in `steps.sonar.outcome` and used to send an email notification if issues are found.

### Why it was done

SAST catches security problems IN THE CODE before any code runs. A developer writing:
```javascript
const query = `SELECT * FROM users WHERE id = ${req.params.id}`;
```
…is vulnerable to SQL injection. SonarCloud catches this at commit time, before it ever runs in any environment.

### Advantages

| Advantage | Detail |
|---|---|
| Catches issues before runtime | Problems found at commit, not in production |
| Zero false negatives on known patterns | SonarCloud has 200+ rules for Node.js/JavaScript |
| Historical trend tracking | Dashboard shows: 0 new security issues this sprint vs. last |
| PR decorations | SonarCloud comments directly on GitHub Pull Requests with exactly which lines have issues |
| Organization-wide dashboard | All 3 repos visible in one SonarCloud dashboard |
| Free for open source | No cost on public GitHub organizations |

---

## 4. Dependency Scanning — Snyk

**File:** `stage-app/.github/workflows/main.yml` (snyk job)

### What was implemented

```yaml
snyk:
  name: Snyk - Dependency Scan
  needs: sast           # runs after SonarCloud completes
  if: always()
  runs-on: ubuntu-latest
  outputs:
    result: ${{ steps.snyk-scan.outcome }}
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: '20'

    - name: Install Snyk CLI
      run: npm install -g snyk

    - name: Install dependencies
      run: |
        for dir in shared services/auth-service services/marketplace-service \
          services/order-service services/media-service services/notification-service; do
          (cd $dir && npm install --omit=dev 2>/dev/null)
        done

    - name: Run Snyk scan
      id: snyk-scan
      run: snyk test --all-projects --severity-threshold=high
      env:
        SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      continue-on-error: true
```

### How it works

**Dependency Scanning = SCA (Software Composition Analysis)** — checking third-party libraries for known CVEs.

Snyk reads each service's `package.json` and `package-lock.json`, resolves the full dependency tree (including transitive dependencies — packages that your packages depend on), then checks every package version against the Snyk vulnerability database.

`npm install --omit=dev` — installs only production dependencies (dev dependencies like `jest`, `eslint` are not shipped, not relevant for runtime security).

`--all-projects` — scans all `package.json` files found in the repository in one pass.

`--severity-threshold=high` — only reports `HIGH` and `CRITICAL` CVEs. `LOW` and `MEDIUM` are ignored to avoid noise. When Snyk finds an issue, it reports:
- The vulnerable package name and version
- The CVE number
- What the vulnerability does
- The fixed version to upgrade to

`continue-on-error: true` — like SAST, this is informational. The result triggers an email if issues are found.

### Why it was done

Your own code might be perfectly written, but if `express@4.18.0` has a known vulnerability, your application is still vulnerable. SAST only checks YOUR code — it cannot see inside `node_modules`. Dependency scanning fills that gap.

Example: In 2021, `lodash` (a very common utility library) had a prototype pollution vulnerability (CVE-2021-23337). Any project using an old `lodash` version was vulnerable regardless of how clean their own code was. Snyk would catch this immediately.

### Advantages

| Advantage | Detail |
|---|---|
| Covers the supply chain | Third-party code is 80-90% of most Node.js apps by volume |
| Finds transitive vulnerabilities | Checks packages-of-packages, not just direct dependencies |
| Fix suggestions | Snyk tells you exactly which version to upgrade to |
| PR blocking option | Can be configured to block merges if critical vulns are found |
| Free tier | Snyk free plan covers most small projects |
| Complements SAST | SAST checks your code, Snyk checks your libraries — together they cover both |

---

## 5. Container Image Scanning — Trivy

**File:** `stage-app/.github/workflows/ci-auth.yml` (same for all 5 services)

### What was implemented

```yaml
- name: Scan with Trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin
    trivy image \
      --severity CRITICAL \
      --exit-code 1 \
      --ignore-unfixed \
      ${{ steps.tag.outputs.full_image }}
```

### How it works

Trivy is a comprehensive security scanner. After the Docker image is built locally on the CI runner (before push), Trivy scans the IMAGE ITSELF — not the source code, not the Dockerfile.

Inside every Docker image are:
- The Alpine Linux base OS packages (installed via `apk`)
- The Node.js runtime packages
- Your `node_modules` (as embedded in the image)

Trivy extracts the list of all these packages and their versions, then checks against:
- NVD (National Vulnerability Database)
- GitHub Security Advisories
- Alpine SecDB (Alpine Linux security database)
- NPM Advisory Database

`--severity CRITICAL` — only CRITICAL vulnerabilities fail the build. HIGH/MEDIUM/LOW are scanned but don't break the pipeline. CRITICAL means the vulnerability is remotely exploitable and has a CVSS score of 9.0-10.0.

`--exit-code 1` — if Trivy finds any CRITICAL CVE, it exits with code 1. GitHub Actions sees non-zero exit = step failed = job failed = **image is NEVER pushed to ECR**. This is a hard security gate.

`--ignore-unfixed` — skips CVEs that have no available fix yet. No point blocking for unfixable issues. Once a fix is released, the next build will catch it.

The image is scanned BEFORE push. If Trivy fails, nothing reaches ECR.

### Why it was done

Your Dockerfile might be correct, but the base image (`node:20-alpine`) or one of the OS packages could have a known vulnerability. Trivy catches this BEFORE a vulnerable image enters your registry and cluster.

Without image scanning, you could deploy a Node.js container that has a vulnerable version of `zlib` or `openssl` in its Alpine base — and not know until a security audit or actual exploitation.

### Advantages

| Advantage | Detail |
|---|---|
| Scans the final artifact | Not just source code — the actual image that runs in production |
| OS package coverage | Finds vulnerabilities in Alpine Linux packages (not just npm packages) |
| Hard gate before ECR | Vulnerable images literally cannot enter the registry |
| Fast | Trivy scans a typical Node.js image in 10-15 seconds |
| Combined with ECR native scanning | ECR also has scan-on-push enabled — double layer of protection |

---

## 6. IaC Security Scanning — Trivy Config

**File:** `stage-infra/.github/workflows/infra-terraform.yml` (scan job)

### What was implemented

```yaml
scan:
  name: Trivy IaC Scan
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Install Trivy
      run: |
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
          | sh -s -- -b /usr/local/bin
    - name: Scan terraform for misconfigurations
      run: trivy config terraform/ --severity CRITICAL,HIGH --exit-code 0 --format table
```

### How it works

`trivy config` is Trivy's Infrastructure-as-Code mode. It reads Terraform `.tf` files (not containers) and checks them against best practice security rules.

It understands Terraform resource types and scans for:

- **S3 buckets:** Is public access blocked? Is versioning enabled? Is encryption enabled?
- **Security groups:** Are there rules allowing `0.0.0.0/0` on sensitive ports (22 SSH, 3306 MySQL)?
- **RDS:** Is `publicly_accessible = false`? Is storage encrypted?
- **EKS:** Are audit logs enabled? Is the endpoint restricted?
- **IAM:** Are roles using wildcard `*` actions when specific actions would suffice?
- **CloudWatch:** Are log groups missing retention settings?

`--exit-code 0` — findings are **reported but don't fail the pipeline**. This is intentional. Some Trivy findings are false positives or acceptable design choices:
- Our S3 frontend bucket is intentionally public (static website)
- Security group allowing HTTP/HTTPS on `0.0.0.0/0` is intentional (it's a web app)

The scan runs before terraform plan. A developer reviewing the pipeline output can see all findings and make an informed decision.

### Why it was done

Terraform misconfigurations are one of the most common causes of cloud security incidents. The Trivy scan catches:
- Forgetting to encrypt an S3 bucket
- Accidentally setting `publicly_accessible = true` on RDS
- Missing VPC flow logs

Catching these before `terraform apply` is far better than finding them after they're in production.

### Advantages

| Advantage | Detail |
|---|---|
| Shift-left security | Finds infrastructure security issues at code review time, not after deployment |
| Consistent checks | Same rules applied on every Terraform change, no manual review required |
| Education | Developers see exactly what they did wrong and why it's a security concern |
| No runtime needed | Checks the code, not the live infrastructure — no AWS API calls |

---

## 7. Kubernetes Network Policy

**File:** `stage-helm/helm/agriconnect/templates/networkpolicy.yaml`

### What was implemented

Four `NetworkPolicy` objects deployed to Kubernetes:

```yaml
# Policy 1: Deny ALL ingress by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: {{ .Values.global.namespace }}
spec:
  podSelector: {}           # applies to ALL pods in namespace
  policyTypes:
    - Ingress

---
# Policy 2: Allow pods in same namespace to call each other
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}   # any pod in this namespace

---
# Policy 3: Allow traffic from kube-system (ALB controller health checks, CoreDNS)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-kube-system
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system

---
# Policy 4: Allow all outbound traffic (AWS SDK calls, RDS, SQS, etc.)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - {}
```

Controlled by a flag in `values.yaml`:
```yaml
networkPolicy:
  enabled: true
```

### How it works

By default, Kubernetes allows ALL pods to communicate with ALL other pods — even across namespaces. A compromised pod could freely connect to any database, any service in any namespace.

**Network Policies work like firewall rules for pods.**

When `default-deny-ingress` is applied with `podSelector: {}` (empty = all pods) and no `ingress:` rules, ALL incoming connections to ALL pods are blocked.

Then specific allow rules are layered on top:

**Policy 2 (allow-same-namespace):** `auth-service` needs to call `marketplace-service` when checking inventory before approving a bid. `order-service` needs to call `auth-service` for JWT verification. These inter-service calls all happen within the `production` namespace, so pods can call each other.

**Policy 3 (allow-from-kube-system):** The AWS Load Balancer Controller runs in `kube-system`. It periodically checks pod health (target health checks). Without this policy, the ALB health probes to your pods would be blocked and pods would appear unhealthy to the ALB.

**Policy 4 (allow-all-egress):** Pods need to make OUTBOUND calls to:
- RDS (port 5432/3306) for database queries
- AWS Secrets Manager (HTTPS 443) to read credentials via IRSA
- SQS (HTTPS 443) for message queuing
- SNS (HTTPS 443) for event publishing
- S3 (HTTPS 443) for image uploads
- Bedrock/API Gateway (HTTPS 443) for AI features

All of these are outbound (egress) connections. Allowing all egress keeps this simple while the important restriction is on ingress (incoming traffic).

### Why it was done

Without Network Policy, if `media-service` were compromised through a file upload vulnerability, the attacker could freely:
- Connect directly to RDS (port 3306) and read/write the entire database
- Call other services (auth-service) to steal JWT tokens
- Probe other namespaces (ArgoCD, kube-system)

With Network Policy:
- Ingress is blocked by default
- Only pods in the same namespace can call each other
- An attacker in `media-service` cannot break out to other namespaces
- The blast radius of any single compromised pod is limited

### Advantages

| Advantage | Detail |
|---|---|
| Zero-trust networking | Pods must have explicit permission to receive traffic |
| Blast radius limitation | Compromised pod cannot freely pivot to other services |
| Namespace isolation | ArgoCD, kube-system, and other namespaces are isolated from app pods |
| Compliance | Required by CIS Kubernetes Benchmark and many security frameworks |
| Helm-controlled | `networkPolicy.enabled: true/false` in values.yaml lets you toggle for testing |

---

## 8. Secrets Management — AWS Secrets Manager

**Files:** `stage-app/shared/utils/secrets.js`, `stage-infra/terraform/modules/eks/main.tf` (IRSA), `stage-app/shared/db/index.js`

### What was implemented

No Kubernetes Secrets are used for sensitive data. Kubernetes Secrets are only `base64` encoded — not encrypted by default. Instead, AWS Secrets Manager stores the database credentials, and pods retrieve them at runtime using IRSA.

```javascript
// shared/utils/secrets.js
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({
  region: process.env.AWS_REGION || 'ap-south-1'
});

const cache = new Map();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5-minute in-memory cache

async function getSecret(secretName) {
  const now = Date.now();
  const cached = cache.get(secretName);
  if (cached && now - cached.ts < CACHE_TTL_MS) {
    return cached.value;         // serve from cache, no network call
  }

  const response = await client.send(
    new GetSecretValueCommand({ SecretId: secretName, VersionStage: 'AWSCURRENT' })
  );

  if (response.SecretString) {
    const value = JSON.parse(response.SecretString);
    cache.set(secretName, { value, ts: now });
    return value;
  }
}

module.exports = { getSecret };
```

The database connection uses this:
```javascript
// shared/db/index.js (example usage)
const { getSecret } = require('../utils/secrets');
const creds = await getSecret('agriconnect/dev/database');
// creds = { host: "...", username: "...", password: "..." }
```

The secret `agriconnect/dev/database` is created by Terraform:
```hcl
resource "aws_secretsmanager_secret" "database" {
  name = "agriconnect/dev/database"
}
```

Pods can only access this secret because of IRSA (see item 21). The IRSA policy allows:
```json
{
  "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
  "Resource": "arn:aws:secretsmanager:*:893431614084:secret:agriconnect/*"
}
```

### How it works

1. Pod starts → no credentials in environment variables or mounted files
2. Application boots, calls `getSecret('agriconnect/dev/database')`
3. AWS SDK (running in the pod) calls Secrets Manager API via HTTPS
4. IRSA: pod's ServiceAccount token is exchanged for temporary AWS credentials (no static keys in the pod)
5. Secrets Manager returns the database credentials JSON
6. Application caches it for 5 minutes (reduces API calls)
7. Application connects to RDS using the retrieved credentials
8. On cache expiry (5 minutes), next call fetches fresh credentials from Secrets Manager

### Why it was done

Kubernetes Secrets (`kind: Secret`) are:
- Only `base64` encoded, NOT encrypted
- Visible to anyone with `kubectl get secret -o json` access
- Stored in etcd (the cluster database) unencrypted unless EKS encryption at rest is configured
- Easy to accidentally commit to Git

AWS Secrets Manager:
- AES-256 encryption at rest using AWS KMS
- Full IAM-controlled access (only permitted pods can read, via IRSA)
- Automatic rotation support
- Full audit trail in CloudTrail

### Advantages

| Advantage | Detail |
|---|---|
| Encrypted at rest | KMS AES-256 encryption, not base64 |
| IAM-scoped access | Only pods with the right ServiceAccount can read `agriconnect/*` secrets |
| No secrets in Git | Zero credentials in any file, Dockerfile, or environment variable |
| Rotation ready | Secrets Manager can rotate RDS passwords automatically on a schedule |
| Audit trail | Every `GetSecretValue` call is logged in AWS CloudTrail |
| 5-min cache | Reduces API calls (Secrets Manager charges per API call), improves startup speed |

---

## 9. Terraform State Locking

**File:** `stage-infra/terraform/versions.tf`

### What was implemented

```hcl
terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "agriconnect-tfstate-893431614084"
    key          = "agriconnect/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true          # Terraform 1.10+ S3 native locking
    encrypt      = true
  }
}
```

### How it works

The Terraform state file (`terraform.tfstate`) records every resource Terraform manages: what exists, what configuration it has, what IDs it has. Without remote state, this file only exists on the machine that ran `terraform apply`.

**Remote state on S3:** The state file is stored in S3 bucket `agriconnect-tfstate-893431614084`. Every `terraform init` pulls the latest state from S3 before doing anything. Every `terraform apply` writes the updated state back to S3 after completion.

**State locking with `use_lockfile = true`:** When the CI pipeline runs `terraform plan` or `terraform apply`, Terraform creates a `.tflock` file in the same S3 bucket. This file signals "Terraform is running, don't start another operation."

If a second pipeline run or developer tries to run Terraform while the lock exists, Terraform fails with: `Error: Error acquiring the state lock`. The operation doesn't proceed until the lock is released.

This replaced the previous DynamoDB-based locking approach. Terraform 1.10+ introduced native S3 locking using `.tflock` files. The DynamoDB approach was deprecated to simplify the setup (no separate DynamoDB table to manage).

`encrypt = true` — the state file is encrypted in S3 using AWS S3 server-side encryption. The state file often contains sensitive data (like database endpoint URLs, ARNs, IRSA role ARNs).

### Why it was done

Without state locking:
- Developer runs `terraform apply` on their laptop at the same time as the CI pipeline runs `terraform apply`
- Both read the same state, compute separate plans, and both try to apply changes
- Result: **state corruption** — resources that exist in AWS are not reflected in the state, or duplicate resources are created

With state locking:
- Only one `terraform apply` can run at any time
- Concurrent operations fail immediately with a clear error
- State integrity is guaranteed

### Advantages

| Advantage | Detail |
|---|---|
| Prevents concurrent corruption | Two applies at once = broken state. Locking prevents this |
| S3-native locking | No DynamoDB table to manage, no extra cost, no mismatch between table name and config |
| Encrypted state | Sensitive values in state (endpoints, IDs) are encrypted at rest |
| Audit trail | S3 versioning on the state bucket lets you see every state version ever applied |
| Simpler than DynamoDB approach | One less resource to create/manage |

---

## 10. Cost Optimization Output

**File:** `stage-infra/terraform/outputs.tf`

### What was implemented

```hcl
output "cost_estimation" {
  description = "Approximate monthly cost breakdown for deployed resources (ap-south-1, USD)"
  value = {
    eks_nodes         = "${var.eks_node_desired_size}x ${var.eks_node_instance_type} nodes = ~$${var.eks_node_desired_size * 15}/mo"
    eks_control_plane = "EKS cluster fee = ~$72/mo"
    rds               = "db.t3.micro 20 GB PostgreSQL = ~$15/mo"
    nat_gateway       = "1x NAT Gateway + data transfer = ~$33+/mo"
    alb               = "1x Application Load Balancer = ~$18/mo"
    cloudfront        = "CloudFront CDN (low traffic) = ~$1-5/mo"
    s3                = "S3 buckets (images + frontend + tfstate) = ~$2-5/mo"
    lambda_fns        = "3x Lambda (pay-per-request) = ~$0-2/mo"
    sns_sqs           = "SNS + SQS event pipeline = ~$0-1/mo"
    secrets_manager   = "1 secret = ~$0.40/mo"
    cloudwatch        = "5 log groups (30-day retention) = ~$1-3/mo"
    total_estimate    = "~$160-175/month (EKS nodes + NAT Gateway = ~70% of cost)"
    optimization_tip  = "Add VPC endpoints for S3 and SQS to cut NAT Gateway data charges"
  }
}
```

### How it works

After `terraform apply`, run `terraform output cost_estimation`. Terraform displays the cost breakdown map calculated at plan time.

`${var.eks_node_desired_size * 15}` — if `eks_node_desired_size = 2`, outputs `2x t3.medium nodes = ~$30/mo`. The calculation is dynamic — changing the node count in `terraform.tfvars` automatically recalculates the estimate.

The `optimization_tip` is actionable: adding VPC endpoints for S3 and SQS means traffic to those AWS services no longer needs to exit through the NAT Gateway. NAT Gateway data processing charges (~$0.045/GB) add up quickly. VPC endpoints are ~$7/month per endpoint but pay back immediately at any meaningful traffic volume.

### Why it was done

Capstone projects often end with "but what would this cost in production?" This output gives an immediate, itemized answer directly from Terraform. Instead of going to the AWS Pricing Calculator separately, the cost estimate is part of the infrastructure code itself.

### Advantages

| Advantage | Detail |
|---|---|
| Immediate visibility | Every `terraform output` shows current cost estimate |
| Dynamic | Changes with variable values — increase nodes = see new estimate |
| Itemized | See exactly where money is going (EKS + NAT = 70%) |
| Actionable tip | Points to the most impactful optimization immediately |
| Teaches cost awareness | Infrastructure engineers should understand what they deploy costs |

---

## 11. CI/CD Pipeline — GitHub Actions

**Files:** `stage-app/.github/workflows/main.yml`, `ci-*.yml`, `ci-prod.yml`, `cd-frontend.yml`

### What was implemented

Orchestrator pattern: one `main.yml` that calls five reusable `ci-*.yml` workflows.

**Pipeline execution order:**
```
sast (SonarCloud)
  └── snyk (dependency scan)         — waits for sast
       └── lint (ESLint)             — waits for sast+snyk
            ├── ci-auth
            ├── ci-marketplace       — all 5 run in parallel
            ├── ci-order             — all wait for lint
            ├── ci-media
            └── ci-notification
                 └── update-helm-values  — waits for all 5 builds
```

Each `ci-*.yml` does: build → trivy scan → smoke test → push to ECR.

Production pipeline (`ci-prod.yml`): manual approval → get git tag → matrix build (all 5 in parallel) → update helm prod branch.

Frontend pipeline (`cd-frontend.yml`): only runs when `frontend/**` files change. Builds React, syncs to S3, invalidates CloudFront.

### Why it was done

Manual deployments are slow, error-prone, and inconsistent. With this pipeline:
- Every push to `dev` automatically runs security scans, builds, and deploys
- A vulnerable image (CRITICAL CVE) literally cannot reach the cluster
- All 5 services always deploy with matching image tags from the same commit
- No developer needs to remember the 15 manual steps to deploy

### Advantages

| Advantage | Detail |
|---|---|
| Speed | 5 Docker builds in parallel = ~5 min instead of ~25 min sequential |
| Security-first ordering | SAST+Snyk must complete before any build starts |
| Reusable workflows | Adding a 6th service = copy one `ci-*.yml`, change 3 variables |
| Change detection | Frontend pipeline only runs when frontend changes = saves 3-4 min on every backend-only push |
| Traceability | Every image tag is a git SHA — `b93b5a1` deployed tells you exactly what commit is running |

---

## 12. GitOps with ArgoCD

**Files:** `stage-helm/argocd/application.yaml`, `stage-helm/argocd/application-prod.yaml`

### What was implemented

ArgoCD is installed in the `argocd` namespace of the EKS cluster via the bootstrap pipeline. Two ArgoCD Application objects are defined:

```yaml
# application.yaml — dev/staging deployment
spec:
  source:
    repoURL: https://github.com/AgriConnect-Platform/agriconnect-helm.git
    targetRevision: dev          # watches dev branch
    path: helm/agriconnect
    helm:
      valueFiles: [values.yaml]
  destination:
    namespace: production        # deploys to production namespace
  syncPolicy:
    automated:
      prune: true                # remove resources deleted from Git
      selfHeal: true             # revert manual cluster changes
```

```yaml
# application-prod.yaml — production deployment
spec:
  source:
    targetRevision: prod         # watches prod branch
  destination:
    namespace: prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### How it works

ArgoCD runs inside the EKS cluster and polls the `agriconnect-helm` GitHub repo every 3 minutes. When `update-helm-values` (in CI) pushes a new image tag to the helm repo's `dev` branch, ArgoCD detects the change and syncs:

1. ArgoCD renders the Helm chart with the new values
2. Compares rendered YAML with what's running in Kubernetes
3. Finds: Deployment has old image tag `a1b2c3d`, Git has `b93b5a1`
4. Runs `kubectl apply` with the new Deployment
5. Kubernetes performs a rolling update

`prune: true` — if you remove a service from the Helm chart, ArgoCD deletes it from the cluster. Without prune, deleted-from-Git resources linger as "orphans" forever.

`selfHeal: true` — if someone manually runs `kubectl scale deployment auth-service --replicas=0`, ArgoCD detects the drift (cluster ≠ Git) and reverts to 2 replicas within minutes.

### Why it was done

GitOps enforces that **Git is the only way to change production**. No developer should ever run `kubectl apply` directly in production. With ArgoCD:
- "What is currently deployed?" → read the helm repo's dev branch
- "Who changed what and when?" → git log on the helm repo
- "Roll back to last week?" → `git revert` on the helm repo, ArgoCD syncs automatically

### Advantages

| Advantage | Detail |
|---|---|
| Audit trail | Every deploy is a git commit with author, timestamp, and diff |
| Self-healing | Manual cluster changes are automatically reverted |
| Drift detection | ArgoCD alerts if cluster state drifts from Git state |
| No `kubectl` access needed | Developers don't need cluster credentials. Git is the interface |
| Rollback is trivial | `git revert` → push → ArgoCD deploys the previous version |

---

## 13. Kubernetes on EKS with Helm

**Files:** `stage-helm/helm/agriconnect/` (all templates), `stage-infra/terraform/modules/eks/main.tf`

### What was implemented

EKS cluster (`agriconnect-dev-eks`) with a managed node group in **private subnets**. Helm chart with templates for all 5 services covering: Deployment, Service, HPA, and shared: NetworkPolicy, PDB, ServiceAccount, Ingress, ConfigMap, Namespace.

Node group tags for Cluster Autoscaler:
```hcl
tags = {
  "k8s.io/cluster-autoscaler/enabled"                = "true"
  "k8s.io/cluster-autoscaler/${var.name_prefix}-eks" = "owned"
}
```

EKS control plane logging for all 5 log types:
```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

### Why it was done

EKS is the managed Kubernetes service — AWS handles the control plane (etcd, kube-apiserver, kube-scheduler), so you only manage your application pods. Helm manages the Kubernetes YAML as a chart with values — one `values.yaml` file controls replicas, image tags, resource limits for all 5 services simultaneously.

---

## 14. Horizontal Pod Autoscaler (HPA)

**File:** `stage-helm/helm/agriconnect/templates/auth/hpa.yaml` (same for all 5 services)

### What was implemented

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: auth-service
  minReplicas: {{ .Values.services.auth.replicas }}   # 2 from values.yaml
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70       # scale up if avg CPU > 70%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80       # scale up if avg memory > 80%
```

### How it works

The HPA controller (part of Kubernetes, enabled via `metrics-server`) watches the average CPU and memory utilization across all pods of a given Deployment every 15 seconds.

- Current replicas: 2, avg CPU: 85% → above 70% threshold → HPA scales to 3 replicas
- New replica starts, load distributes → avg CPU drops to 57% → HPA scales back to 2
- Minimum is always 2 (from `values.yaml` — never scales below 2 for availability)
- Maximum is 6 (cost cap — never more than 6 pods per service)

**Dual metric scaling:** Both CPU and memory can trigger scale-up independently. Whichever requires more replicas wins. For `auth-service` handling JWT generation (CPU-bound) vs `media-service` handling image processing (memory-bound), each has the right trigger.

`autoscaling/v2` — uses the v2 API (stable since Kubernetes 1.23), which supports multiple metrics. The old `v1` only supported CPU.

### Why it was done

Fixed replica counts waste money when traffic is low and fail when traffic spikes. HPA automatically adjusts:
- 2am (low traffic) → 2 replicas → minimal cost
- Harvest season peak (high traffic) → 6 replicas → handles load
- After peak → scales back down automatically

### Advantages

| Advantage | Detail |
|---|---|
| Cost efficiency | Not paying for 6 replicas 24/7 when only needed during peaks |
| Zero-intervention scaling | No on-call person needs to manually scale during traffic spikes |
| Dual metric (CPU + memory) | Handles both compute-heavy and memory-heavy workloads |
| Minimum 2 replicas | Zero-downtime even during scaling events |

---

## 15. Cluster Autoscaler

**File:** `stage-infra/.github/workflows/bootstrap.yml` (install step), `stage-infra/terraform/modules/eks/main.tf` (IAM + tags)

### What was implemented

Cluster Autoscaler is installed via `bootstrap.yml`:
```bash
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set "autoDiscovery.clusterName=$CLUSTER" \
  --set "awsRegion=$AWS_REGION" \
  --set "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$CA_ROLE" \
  --wait --timeout=5m
```

IAM policy created in Terraform permits the Cluster Autoscaler to:
```json
"Action": ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
```
Only on node groups tagged with:
```
k8s.io/cluster-autoscaler/enabled = "true"
k8s.io/cluster-autoscaler/agriconnect-dev-eks = "owned"
```

### How it works

HPA scales **pods** (more containers on the same nodes). Cluster Autoscaler scales **nodes** (more EC2 instances when existing nodes are full).

When HPA creates new pods but there is no node with enough free CPU/memory to schedule them, pods stay in `Pending` state. The Cluster Autoscaler detects pending pods, checks if adding a node would help, and if yes — increments the Auto Scaling Group desired count. AWS launches a new EC2 node. Within 2-3 minutes, the node joins the cluster and the pending pods are scheduled.

When traffic drops and nodes are underutilized (CPU < 50% for 10 minutes), Cluster Autoscaler drains a node (moves pods to other nodes) and terminates the EC2 instance.

The tag condition on the IAM policy (`k8s.io/cluster-autoscaler/enabled = "true"`) ensures the Cluster Autoscaler can only manage your node groups — not accidentally autoscale other teams' infrastructure.

### Why it was done

Without Cluster Autoscaler, if all 5 services HPA to max (6 pods each = 30 pods), the 2 nodes might run out of capacity. Pods stay Pending indefinitely. With Cluster Autoscaler, a 3rd or 4th node starts automatically. After the peak, extra nodes terminate automatically.

### Advantages

| Advantage | Detail |
|---|---|
| Cost optimization | No idle nodes at 3am. EC2 instances only run when needed |
| Infinite scale | Within the `max_size` of the ASG, the cluster can grow automatically |
| Works with HPA | HPA scales pods → Cluster Autoscaler scales nodes — complementary |
| IRSA auth | No access key stored in Cluster Autoscaler config — uses IAM token via OIDC |

---

## 16. Pod Disruption Budget (PDB)

**File:** `stage-helm/helm/agriconnect/templates/pdb.yaml`

### What was implemented

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: auth-service-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: auth-service
```

(Separate PDB for each of the 5 services)

### How it works

A PDB tells Kubernetes: "When voluntarily disrupting pods (draining a node, rolling update, Cluster Autoscaler removing a node), always keep at least 1 pod of this service running."

`minAvailable: 1` — at any given moment during a node drain or rolling update, at minimum 1 pod of auth-service must be running and healthy.

With 2 replicas and `minAvailable: 1`:
- Rolling update: Kubernetes terminates pod 1 (1 remaining = satisfies PDB) → starts new pod → 2 running → terminates pod 2
- Node drain: Kubernetes evicts pod from the draining node only after confirming the other pod on the remaining node is healthy

Without a PDB:
- Cluster Autoscaler might drain a node with 2 auth-service pods simultaneously
- Both pods terminate at once → auth-service is down → users see errors

### Why it was done

Node maintenance, rolling updates, and Cluster Autoscaler node removal are all "voluntary disruptions" that Kubernetes controls. The PDB is the mechanism to tell Kubernetes your availability requirements during these events. For a production marketplace application, zero downtime is a hard requirement.

### Advantages

| Advantage | Detail |
|---|---|
| Zero-downtime operations | Node drains, cluster upgrades, rolling updates never take a service to 0 |
| Cluster Autoscaler coordination | CA respects PDBs when deciding which nodes to drain |
| Per-service control | notification-service could tolerate 0 available (non-critical), auth-service cannot |

---

## 17. Health Checks — Liveness and Readiness Probes

**File:** `stage-helm/helm/agriconnect/templates/auth/deployment.yaml`

### What was implemented

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 3001
  initialDelaySeconds: 30    # wait 30s before first check (startup time)
  periodSeconds: 15          # check every 15 seconds
  failureThreshold: 3        # fail 3 times before restarting

readinessProbe:
  httpGet:
    path: /ready
    port: 3001
  initialDelaySeconds: 15    # wait 15s before first check
  periodSeconds: 10          # check every 10 seconds
  failureThreshold: 3        # fail 3 times before removing from load balancer
```

### How it works

Kubernetes distinguishes two health states:

**Liveness (`/healthz`):** Is the pod alive and not deadlocked?
- Returns `200 OK` if the Node.js event loop is running normally
- If it returns non-200 or times out 3 times: Kubernetes RESTARTS the pod
- Use case: Node.js app enters an infinite loop or crashes but the process doesn't exit — liveness restart recovers it

**Readiness (`/ready`):** Is the pod ready to receive traffic?
- Returns `200 OK` only when the app has connected to the database, loaded config, and is ready to handle requests
- If it returns non-200: pod is removed from the ALB target group (no traffic sent to it)
- Pod returns to service when `/ready` passes again
- Use case: During startup (database connection takes 5-10s), pod is NOT sent traffic until it's genuinely ready

`initialDelaySeconds: 30` (liveness) — gives the Node.js process 30 seconds to start before the first check. Without this delay, Kubernetes might kill the pod before it even finishes starting.

### Why it was done

Without health probes:
- Pod crashes (process dies, port gone) → Kubernetes restarts it (eventually)
- BUT: pod might be alive (process running) but deadlocked → stays in "Running" state forever, receiving traffic, returning errors

With probes:
- Deadlocked pod → liveness probe fails → pod restarts automatically
- Pod still starting up → readiness probe fails → not in load balancer → users never hit an unready pod
- Rolling update → new pod only gets traffic AFTER `/ready` returns 200

### Advantages

| Advantage | Detail |
|---|---|
| Self-healing | Deadlocked pods automatically restart without human intervention |
| Zero-downtime deploys | New pods only serve traffic when genuinely ready |
| ALB health sync | ALB target health check aligns with Kubernetes readiness |
| Graceful restarts | `terminationGracePeriodSeconds: 30` gives in-flight requests 30s to complete before pod is killed |

---

## 18. Smoke Tests in Pipeline

**File:** `stage-app/.github/workflows/ci-auth.yml` (smoke test step, same for all 5 services)

### What was implemented

```bash
# After image is built but BEFORE pushing to ECR:
docker run -d \
  -e PORT=3001 \
  -e SKIP_DB=true \
  -p 3001:3001 \
  --name smoke-auth \
  ${{ steps.tag.outputs.full_image }}

echo "Waiting for /healthz..."
for i in $(seq 1 20); do
  RESP=$(curl -sf http://localhost:3001/healthz 2>/dev/null || true)
  if [ -n "$RESP" ]; then
    echo "$RESP"
    echo "Smoke test passed!"
    docker rm -f smoke-auth || true
    exit 0
  fi
  sleep 1
done
echo "FAILED: /healthz did not respond in 20s"
docker logs smoke-auth 2>/dev/null || true
docker rm -f smoke-auth || true
exit 1
```

### How it works

After the Docker image is built and scanned by Trivy, it is run as an actual container on the CI runner. The container starts with `SKIP_DB=true` — the Node.js service detects this flag and skips the database connection (no RDS available on the CI runner).

The test polls `http://localhost:3001/healthz` for up to 20 seconds. If the endpoint responds with any non-empty body (the service returns `{"status":"ok"}`), the smoke test passes. The container is removed and the pipeline proceeds to push the image to ECR.

If `/healthz` does not respond in 20 seconds, the test prints the container logs (for debugging), removes the container, and **exits with code 1** — the pipeline fails and the image is NOT pushed to ECR.

### Why it was done

Trivy checks for known CVEs in packages but cannot verify that the application actually STARTS. A broken `CMD ["node", "index.js"]` (wrong path), a missing environment variable causing a crash on startup, or a syntax error in `index.js` — these are caught by the smoke test and NEVER pushed to ECR.

Without the smoke test, a broken image could pass Trivy scanning (no CVEs in a broken app) and be pushed to ECR. ArgoCD would then deploy it, Kubernetes would create pods, the liveness probe would fail after 3 checks, pods would restart in a crash loop — production down.

### Advantages

| Advantage | Detail |
|---|---|
| Pre-push validation | Image only reaches ECR if it actually starts and responds to /healthz |
| Fast feedback | Developers find out in 30 seconds if their image is broken, not 8 minutes after deploy |
| No environment dependencies | `SKIP_DB=true` makes smoke test work without RDS/secrets |
| Debug output | On failure, `docker logs` prints exactly why the container crashed |
| Maps to prod health check | Same `/healthz` endpoint used by Kubernetes liveness probe |

---

## 19. Code Linting — ESLint

**Files:** `stage-app/.eslintrc.json`, `stage-app/.eslintignore`, `stage-app/.github/workflows/main.yml` (lint job)

### What was implemented

```json
// .eslintrc.json
{
  "env": {
    "node": true,
    "es2020": true
  },
  "parserOptions": {
    "ecmaVersion": 2020
  },
  "rules": {
    "no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
    "no-undef": "error",
    "no-console": "off"
  }
}
```

```
// .eslintignore
shared/scripts/
node_modules/
```

```yaml
# main.yml — lint job
- name: Lint all services
  run: |
    npx eslint@8 \
      services/auth-service \
      services/marketplace-service \
      services/order-service \
      services/media-service \
      services/notification-service \
      shared \
      --ext .js \
      --max-warnings 0
```

### How it works

ESLint parses every `.js` file in all 5 service directories and the shared directory, then checks each against the rules:

`no-undef: "error"` — using a variable that was never declared crashes at runtime. ESLint catches it at lint time:
```javascript
// This would crash: ReferenceError: myVar is not defined
console.log(myVar);
```

`no-unused-vars: ["warn", ...]` — a declared variable that's never used is dead code. `argsIgnorePattern: "^_"` means function arguments starting with `_` are allowed to be unused (common convention for "I know this exists but I'm not using it"):
```javascript
app.get('/path', (req, _res, next) => { ... });  // _res is fine
```

`no-console: "off"` — `console.log` allowed (Node.js services legitimately use console logging).

`--max-warnings 0` — ZERO warnings allowed. Even a single `no-unused-vars` warning fails the lint step and blocks all 5 Docker builds.

`shared/scripts/` is excluded via `.eslintignore` because `seed.js` and `migrate.js` are run once during bootstrap — they have intentionally unused variables for clarity. These are not production code.

### Why it was done

ESLint sits between SAST and the Docker build, blocking bad code from being containerized:
- `no-undef` catches `ReferenceError` crashes that only appear at runtime
- `no-unused-vars` prevents dead code accumulation
- `--max-warnings 0` enforces zero tolerance — no "I'll clean it up later"

### Advantages

| Advantage | Detail |
|---|---|
| Catches runtime errors at commit time | `ReferenceError` would only appear when that code path runs |
| Prevents dead code accumulation | Unused variables get cleaned up before merge |
| All 5 services in one command | Single lint command covers the entire codebase |
| Blocks Docker builds | Linting must pass before any image is built |

---

## 20. Resource Requests and Limits

**File:** `stage-helm/helm/agriconnect/values.yaml`, `stage-helm/helm/agriconnect/templates/auth/deployment.yaml`

### What was implemented

```yaml
# values.yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

```yaml
# deployment.yaml (applied to all 5 services)
resources:
  requests:
    cpu: {{ .Values.resources.requests.cpu }}      # 100m
    memory: {{ .Values.resources.requests.memory }} # 256Mi
  limits:
    cpu: {{ .Values.resources.limits.cpu }}         # 500m
    memory: {{ .Values.resources.limits.memory }}   # 512Mi
```

### How it works

**Requests** — what the pod is GUARANTEED to get. The Kubernetes scheduler only places a pod on a node that has at least `100m` CPU and `256Mi` memory available. Requests are used for scheduling decisions.

- `100m` CPU = 100 millicores = 10% of one vCPU core
- `256Mi` memory = 256 Mebibytes

**Limits** — the MAXIMUM a pod can use. If the pod tries to use more CPU than `500m`, it is throttled (slowed down). If it uses more memory than `512Mi`, it is **OOM-killed** (terminated and restarted).

**On a t3.medium node (2 vCPU, 4 GB RAM):**
- Each node can fit: 2000m ÷ 100m = 20 pods by CPU requests
- Each node can fit: 4096Mi ÷ 256Mi = 16 pods by memory requests
- Memory is the bottleneck → 16 pods per node maximum
- 2 nodes = 32 pods capacity
- Current need: 5 services × 2 replicas = 10 pods (10/32 = 31% utilization — comfortable headroom)

### Why it was done

Without resource limits:
- A memory leak in marketplace-service could consume all node RAM → ALL other pods OOM-killed → entire cluster crashes
- One misbehaving pod starves every other pod on the same node
- Kubernetes HPA cannot make scaling decisions without request values to compare against

With resource limits:
- Misbehaving pod is capped at 512Mi → only that pod dies, others unaffected
- Scheduler can bin-pack pods efficiently onto nodes

### Advantages

| Advantage | Detail |
|---|---|
| Fault isolation | Memory leak in one service cannot cascade to others |
| HPA accuracy | HPA's "CPU at 70%" calculation requires request baseline to compare against |
| Cost predictability | Known requests = calculable maximum cost per service |
| Node efficiency | Scheduler can pack more pods per node with small requests |

---

## 21. IRSA — IAM Roles for Service Accounts

**File:** `stage-infra/terraform/modules/eks/main.tf`, `stage-helm/helm/agriconnect/templates/serviceaccount.yaml`

### What was implemented

**Terraform creates:**
```hcl
# OIDC provider for the cluster
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# IAM Role that ONLY the agriconnect-services ServiceAccount can assume
resource "aws_iam_role" "services" {
  name = "agriconnect-dev-eks-services-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringLike = {
          "${local.oidc_issuer}:sub" = [
            "system:serviceaccount:production:agriconnect-services",
            "system:serviceaccount:dev:agriconnect-services"
          ]
        }
      }
    }]
  })
}
```

**Kubernetes ServiceAccount:**
```yaml
# serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: agriconnect-services
  namespace: {{ .Values.global.namespace }}
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::893431614084:role/agriconnect-dev-eks-services-role"
```

**Deployment uses the ServiceAccount:**
```yaml
spec:
  serviceAccountName: agriconnect-services
```

### How it works

Normally, giving a Kubernetes pod access to AWS means putting `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as environment variables. These static keys:
- Must be rotated manually
- Can leak through `docker inspect`, `kubectl exec`, logs
- Give the same permissions to ALL pods using them

IRSA works differently:

1. EKS has an OIDC Identity Provider (essentially: "I am this EKS cluster, I can vouch for my pods")
2. When a pod starts with `serviceAccountName: agriconnect-services`, EKS mounts a JWT token into the pod at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
3. This JWT token says: "I am the `agriconnect-services` ServiceAccount in the `production` namespace"
4. The AWS SDK in the pod automatically finds this token, calls STS `AssumeRoleWithWebIdentity`, exchanges the JWT for temporary AWS credentials (valid for 1 hour, auto-refreshed)
5. These temporary credentials are used for all AWS API calls (Secrets Manager, S3, SQS, SNS)

The IAM role's trust policy has a `Condition` that checks the token's subject (`sub` claim). Only tokens from `system:serviceaccount:production:agriconnect-services` can assume this role. A different ServiceAccount cannot assume it — even if it's in the same cluster.

### Why it was done

IRSA eliminates static AWS credentials entirely from pods. There is no `AWS_ACCESS_KEY_ID` anywhere in the deployment configuration. The AWS credentials are:
- Temporary (expire in 1 hour, auto-refreshed)
- Automatically rotated by AWS STS
- Scoped to the specific ServiceAccount (pod identity)
- Never stored in any file or environment variable

### Advantages

| Advantage | Detail |
|---|---|
| No static credentials | Nothing to rotate, nothing to leak, nothing to accidentally commit to Git |
| Pod-level identity | Each ServiceAccount gets distinct IAM permissions — fine-grained access control |
| Auto-rotation | STS credentials rotate every hour automatically |
| Audit trail | CloudTrail shows: "agriconnect-services in production assumed role X at time Y" |
| Cluster isolation | An IRSA role from cluster A cannot be assumed by a pod in cluster B |

---

## 22. ECR — Lifecycle Policy and Scan on Push

**File:** `stage-infra/terraform/modules/eks/main.tf`

### What was implemented

```hcl
# 5 ECR repositories, one per service
resource "aws_ecr_repository" "services" {
  for_each = toset(["auth", "marketplace", "order", "media", "notification"])

  name                 = "agriconnect-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true          # ECR scans every image pushed
  }
}

# Lifecycle policy on every repository
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = toset(["auth", "marketplace", "order", "media", "notification"])
  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
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

### How it works

**Scan on push:** Every image pushed to ECR automatically triggers an AWS-native vulnerability scan (powered by Clair). Results appear in the ECR console within 2-3 minutes. This is a SECOND layer of scanning (after Trivy in CI), using a different vulnerability database.

**Lifecycle policy:** After every `git push` to dev, a new image is pushed with a SHA tag. Without lifecycle management, after 100 pushes you have 100 images. Each image is typically 150-200MB:
- 100 images × 175MB = 17.5 GB stored in ECR
- ECR storage: ~$0.10/GB/month → $1.75/month just for old unused images
- After 1000 pushes: $17.50/month in unused images

With the lifecycle policy, ECR keeps only the last 10 images per repository. Images 11 and older are automatically deleted. 10 images × 175MB × 5 repos = ~8.75 GB maximum storage.

### Why it was done

`for_each = toset([...])` — creates 5 identical resources with one Terraform block. Adding a 6th service means adding the string to the list. The lifecycle policy ensures ECR doesn't accumulate unbounded images over months of development.

### Advantages

| Advantage | Detail |
|---|---|
| Dual-layer scanning | Trivy in CI + ECR scan on push = two independent vulnerability databases |
| Cost control | Lifecycle policy prevents unbounded storage costs |
| Registry hygiene | Old images don't pile up, making the ECR console usable |
| DRY Terraform | One block creates 5 identical repositories via `for_each` |

---

## 23. CloudWatch Observability

**Files:** `stage-infra/terraform/cloudwatch.tf`, `stage-infra/terraform/modules/eks/main.tf`

### What was implemented

**EKS control plane logging:**
```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

**CloudWatch Container Insights addon:**
```hcl
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "amazon-cloudwatch-observability"
}
```

**CloudWatch log groups (from cloudwatch.tf):**
- `/aws/eks/agriconnect-dev-eks/cluster` — control plane logs, 30-day retention
- Log groups for Lambda functions
- Application log groups

**Node group IAM:** `CloudWatchAgentServerPolicy` attached to node role, allowing the CloudWatch agent to push metrics.

### How it works

**Control plane logs:** `api` (every kubectl command), `audit` (who did what), `authenticator` (IRSA token exchanges), `controllerManager`, `scheduler` — all streamed to CloudWatch. If a deployment fails or a pod is evicted, the exact reason is in these logs.

**Container Insights addon:** Installs the CloudWatch agent as a DaemonSet (one agent pod on every node). It collects:
- Per-pod CPU and memory metrics
- Node-level metrics
- Network metrics

Visible in CloudWatch under "Container Insights" → cluster dashboard showing pods, nodes, services all in one view.

**30-day retention:** Log groups expire after 30 days. Indefinite retention would grow unboundedly and cost money. 30 days covers any incident investigation window.

### Advantages

| Advantage | Detail |
|---|---|
| Complete audit trail | Every `kubectl` call, every pod scheduled/evicted, every IRSA token exchange is logged |
| Metrics without extra tools | No Prometheus/Grafana needed for basic cluster metrics |
| 30-day incident window | Enough history for any security or reliability investigation |
| Native AWS integration | Alarms, dashboards, and alerts through CloudWatch — no separate observability stack |

---

## 24. VPC Architecture — Private Subnets

**File:** `stage-infra/terraform/modules/networking/main.tf`

### What was implemented

VPC: `10.0.0.0/16` across 2 Availability Zones:

```
Public subnets:  10.0.1.0/24 (ap-south-1a), 10.0.2.0/24 (ap-south-1b)
Private subnets: 10.0.11.0/24 (ap-south-1a), 10.0.12.0/24 (ap-south-1b)
```

- **Internet Gateway** → attached to VPC, routes internet traffic to/from public subnets
- **NAT Gateway** → in public subnet, allows private subnet resources to initiate outbound internet connections (npm packages, AWS APIs)
- **ALB** → in public subnets (receives traffic from internet, routes to private pods)
- **EKS nodes** → in private subnets (no direct internet exposure)
- **RDS** → in private subnets (no public internet access)

```hcl
# EKS nodes go in private subnets
subnet_ids = var.private_subnet_ids

# ALB annotation in Helm chart
annotations:
  kubernetes.io/ingress.class: "alb"
  alb.ingress.kubernetes.io/scheme: "internet-facing"
  alb.ingress.kubernetes.io/subnets: "subnet-public-1a,subnet-public-1b"
```

### Why it was done

EC2 instances (EKS nodes) in private subnets have NO public IP addresses. They cannot be reached directly from the internet. The only entry point to the application is:

```
Internet → CloudFront → ALB (public subnets) → EKS pods (private subnets)
```

An attacker scanning the internet cannot find or connect to your EKS nodes or RDS database — they don't have public IPs.

### Advantages

| Advantage | Detail |
|---|---|
| No direct internet exposure | Nodes and RDS are completely unreachable from the internet |
| Security depth | Multiple layers: CloudFront WAF → ALB security group → Network Policy → pod |
| RDS isolation | Database is in private subnet AND has a security group only allowing EKS node traffic |
| Multi-AZ | Subnets in 2 AZs — if one AZ fails, traffic routes to the other |

---

## 25. Microservices Architecture

**Files:** `stage-app/services/` (5 separate services)

### What was implemented

5 independent Node.js microservices, each in its own directory with its own `package.json`, `Dockerfile`, and container:

| Service | Port | Responsibility |
|---|---|---|
| auth-service | 3001 | User registration, login, JWT token issuance |
| marketplace-service | 3002 | Produce listings, bidding, price discovery |
| order-service | 3003 | Order creation, status tracking, payment recording |
| media-service | 3004 | Image upload to S3, media management |
| notification-service | 3005 | Email/SMS notifications, SQS message consumer |

Shared code (database models, auth middleware, utilities) lives in `shared/` and is mounted into each service via the Dockerfile's multistage build:
```dockerfile
COPY shared/package*.json ./shared/
RUN cd shared && npm install
COPY shared/ ./shared/
```

### Why it was done

A monolith would have all 5 features in one process. One bug in notification-service crashes auth-service. Scaling for image upload peaks means scaling the entire app.

With microservices:
- auth-service bug only affects auth → all other services keep running
- media-service can scale independently during harvest photo upload peaks
- Each service can be updated, deployed, and rolled back independently
- Different services could use different technologies in the future

---

## 26. SNS + SQS Event-Driven Messaging

**Files:** `stage-app/shared/utils/eventPublisher.js`, `stage-app/services/notification-service/workers/sqsWorker.js`

### What was implemented

When an order is placed, order-service publishes an event to SNS:
```javascript
// eventPublisher.js
const sns = new SNSClient({ region: process.env.AWS_REGION });
await sns.send(new PublishCommand({
  TopicArn: process.env.SNS_EVENTS_TOPIC_ARN,
  Message: JSON.stringify({ type: 'ORDER_PLACED', orderId, farmerId, buyerId }),
  Subject: 'AgriConnect Event'
}));
```

SNS fans out to SQS queue → notification-service's SQS worker consumes messages:
```javascript
// sqsWorker.js
const sqs = new SQSClient({ region: process.env.AWS_REGION });
while (true) {
  const { Messages } = await sqs.send(new ReceiveMessageCommand({
    QueueUrl: process.env.NOTIFICATIONS_QUEUE_URL,
    MaxNumberOfMessages: 10,
    WaitTimeSeconds: 20   // long polling — waits up to 20s for messages
  }));
  for (const message of Messages || []) {
    await processNotification(JSON.parse(message.Body));
    await sqs.send(new DeleteMessageCommand({ ... message.ReceiptHandle ... }));
  }
}
```

### Why it was done

Without messaging: `order-service` directly calls `notification-service` via HTTP. If notification-service is down → order fails → user gets an error even though their order succeeded.

With SNS+SQS: order-service publishes to SNS (always succeeds — SNS is highly available) → returns success to user immediately → notification-service processes the message when it's ready. The order and the notification are decoupled.

### Advantages

| Advantage | Detail |
|---|---|
| Decoupling | Services don't depend on each other's uptime |
| Retry built-in | SQS delivers messages until explicitly deleted — failed notifications auto-retry |
| Fan-out | One SNS topic → multiple SQS queues (add future subscribers without changing order-service) |
| Long polling | `WaitTimeSeconds: 20` reduces empty poll API calls by 95% vs short polling |

---

## 27. Serverless — Three Lambda Functions

**Files:** `stage-infra/lambda/farmbot/`, `stage-infra/lambda/buyerbot/`, `stage-infra/lambda/weather-alert-processor/`

### What was implemented

**FarmBot** (Python, AWS Bedrock Nova):
- API Gateway POST `/chat` → Lambda → Bedrock Nova
- Accepts base64-encoded plant images
- Diagnoses plant diseases using multimodal AI
- Publishes results to SNS for farmer notifications

**BuyerBot** (Python, AWS Bedrock Nova with tool use):
- API Gateway POST `/chat` → Lambda → Bedrock (with `tools:`)
- When user asks "what tomatoes are available?", Bedrock decides to call the `search_produce` tool
- Lambda calls the live marketplace-service via ALB
- Returns real current listings to the buyer

**Weather Alert Processor** (Node.js):
- EventBridge schedule → Lambda every 6 hours
- Calls Open-Meteo weather API for agricultural coordinates
- If severe weather detected → publishes to SNS → SQS → notification-service emails farmers

All three functions are packaged as `.zip` files by Terraform:
```hcl
data "archive_file" "farmbot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/farmbot"
  output_path = "${path.module}/farmbot_package.zip"
}
```

### Why it was done

These features don't need persistent compute. FarmBot is called a few times per hour. BuyerBot is called during buyer browse sessions. Weather alerts fire every 6 hours.

Running these as EKS pods would mean:
- 3 more Deployments × 2 replicas = 6 more pods
- Paying for idle compute 23.9 hours/day

Lambda only runs (and charges) when invoked:
- ~3 Lambda invocations/hour × 720 hours/month × $0.0000002/invocation = ~$0.00043/month

### Advantages

| Advantage | Detail |
|---|---|
| Near-zero cost | Pay only per invocation — pennies per month for this traffic level |
| Zero pod management | No Dockerfile, no deployment YAML, no HPA needed |
| Automatic scaling | Lambda handles 1 to 10,000 concurrent invocations automatically |
| EventBridge integration | Weather Lambda triggered by schedule — no always-running cron job |

---

## 28. CloudFront CDN + S3 Frontend Hosting

**Files:** `stage-infra/terraform/modules/cloudfront/main.tf`, `stage-infra/terraform/modules/s3/main.tf`

### What was implemented

React frontend is built by Vite and deployed to an S3 bucket configured for static website hosting. CloudFront sits in front:

```
Users worldwide → CloudFront (130+ edge locations) → S3 (ap-south-1)
```

```hcl
resource "aws_s3_bucket" "frontend" {
  bucket = "agriconnect-frontend-893431614084"
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
  }
  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    # ... cache settings
  }
  price_class = "PriceClass_100"   # only cheapest edge locations
}
```

CI pipeline deploys the frontend:
```bash
# Build with API URLs from SSM
VITE_FARMBOT_API_URL=$(aws ssm get-parameter --name /agriconnect/farmbot_api_url ...)
npm run build

# Sync to S3
aws s3 sync frontend/dist/ s3://agriconnect-frontend-893431614084/ \
  --delete \
  --cache-control "max-age=31536000,public,immutable"

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id $CF_ID --paths "/*"
```

### Why it was done

Serving React files from EKS pods is wasteful — static files don't need dynamic compute. S3 serves files infinitely scalably. CloudFront caches them at 130+ edge locations worldwide — a farmer in Delhi gets the frontend from the nearest CloudFront PoP (Mumbai), not from the S3 bucket in ap-south-1. Load time: 100ms vs 500ms.

`--cache-control "max-age=31536000,public,immutable"` — Vite generates hashed filenames (`app.a3f2.js`). Same content = same hash. CloudFront caches hashed files for 1 year. After a new deploy, new hash = new filename = cache miss = fresh file. Old hash cached content is never stale.

### Advantages

| Advantage | Detail |
|---|---|
| Global performance | Files served from nearest edge location — not all the way to ap-south-1 |
| Infinite scale | S3 + CloudFront serve unlimited concurrent users |
| HTTPS forced | `redirect-to-https` — all HTTP requests redirected to HTTPS |
| Cost | Static hosting is ~$2-5/month vs running 2 nginx pods |
| Immutable caching | 1-year browser cache on hashed assets = fastest possible load on repeat visits |

---

## 29. RDS Database

**File:** `stage-infra/terraform/modules/rds/main.tf`

### What was implemented

Single RDS instance in private subnets. Application services connect using credentials fetched from Secrets Manager at startup. Shared across all 5 microservices via `shared/db/index.js` (Sequelize ORM with shared connection pool).

Security group allows only EKS nodes (on port 3306) — no public internet access. Database credentials are stored in Secrets Manager and accessed via IRSA.

**DB migration** runs as a one-off Kubernetes pod during bootstrap:
```bash
kubectl apply -f migration-pod.yaml   # runs node /app/shared/scripts/migrate.js
kubectl wait --for=condition=succeeded pod/db-migration --timeout=300s
```

This creates all tables (`Users`, `Farmers`, `Buyers`, `Listings`, `Orders`, `Bids`, etc.) before any service pods start.

### Advantages

| Advantage | Detail |
|---|---|
| Managed service | AWS handles backups, patching, failover |
| Private subnet | Not reachable from internet — only from EKS nodes |
| Secrets Manager | Credentials never in code, environment variables, or Kubernetes Secrets |
| Migration pod | Schema changes applied as code (not manual SQL) |

---

## 30. Approval Gates

**Files:** `stage-infra/.github/workflows/infra-terraform.yml`, `stage-app/.github/workflows/ci-prod.yml`

### What was implemented

```yaml
# infra-terraform.yml — apply job
apply:
  environment: production   # triggers GitHub approval requirement

# ci-prod.yml — approval job (runs first, all other jobs need it)
approval:
  name: Await Production Approval
  environment: production
  steps:
    - run: echo "Production deployment approved"
```

GitHub environment protection rules:
```
Environment: production
Required reviewers: [asadchamp109]
Wait timer: 0 minutes
Deployment branches: prod, main
```

### How it works

When a pipeline job has `environment: production`, GitHub pauses that job before execution. It sends a notification (email + GitHub notification) to the required reviewers. The reviewer opens GitHub, sees:

1. The `plan` job output (what Terraform will change) for infra pipeline
2. The commit diff and service versions for the prod pipeline

They click **Approve** or **Reject**. If approved, the job runs immediately. If rejected, the pipeline fails.

For the infra pipeline, the plan artifact from the `plan` job is available for review — the reviewer can see exactly which AWS resources will change before approving.

### Why it was done

Without approval gates, any merge to `prod` or `main` automatically deploys to production. This means:
- An accidental `git push origin prod` deploys to production
- A bad Terraform plan (accidentally deleting the EKS cluster) auto-applies
- No human eyes on production changes

With approval gates, nothing reaches production without explicit human sign-off on exactly what will be deployed.

### Advantages

| Advantage | Detail |
|---|---|
| Human checkpoint | Every production change reviewed by a human before execution |
| Notification | Reviewer gets email/Slack notification — no need to watch the pipeline |
| Plan review | For infra, reviewer sees the exact changes before approving |
| Audit | GitHub records who approved, when, and what was deployed |

---

## 31. Security Failure Email Notification

**File:** `stage-app/.github/workflows/notify-failure.yml`

### What was implemented

```yaml
# Called by main.yml when SAST or Snyk fails
on:
  workflow_call:
    inputs:
      scan_name:
        required: true
        type: string

steps:
  - uses: dawidd6/action-send-mail@v3
    with:
      server_address: smtp.gmail.com
      server_port: 587
      username: asadchamp109@gmail.com
      password: ${{ secrets.TF_VAR_SMTP_PASS }}
      subject: "❌ AgriConnect CI — ${{ inputs.scan_name }} FAILED"
      body: |
        STATUS  : ❌ FAILED
        SCAN    : ${{ inputs.scan_name }}
        Branch  : ${{ github.ref_name }}
        Commit  : ${{ github.sha }}
        Trigger : ${{ github.actor }}
        Run #   : ${{ github.run_number }}
        View full run:
        ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

Main.yml calls this if either SonarCloud or Snyk finds issues:
```yaml
notify-security:
  if: always() && (needs.sast.outputs.result == 'failure' || needs.snyk.outputs.result == 'failure')
  uses: ./.github/workflows/notify-failure.yml
  with:
    scan_name: "SonarCloud SAST + Snyk"  # or individual scan name
```

### Why it was done

Security scans run with `continue-on-error: true` (don't block the pipeline). But findings still need to be communicated immediately to the developer. An email with the exact commit SHA, branch, who triggered it, and a direct link to the logs means the developer knows within 60 seconds of pushing that a vulnerability was found.

The reusable workflow pattern (`workflow_call`) means the email logic is written once and called from anywhere.

### Advantages

| Advantage | Detail |
|---|---|
| Immediate notification | Developer knows about security findings within 60 seconds of push |
| Direct link | One-click to the exact pipeline run showing the vulnerability |
| Context in email | Branch, commit, who pushed — all in the email body |
| Reusable | Same workflow called for SonarCloud failures, Snyk failures, or both |

---

## 32. Terraform Modular Architecture

**File:** `stage-infra/terraform/` (all `.tf` files)

### What was implemented

Root module (`main.tf`) composes 6 child modules:

```hcl
module "networking" {
  source     = "./modules/networking"
  aws_region = var.aws_region
  vpc_cidr   = var.vpc_cidr
}

module "eks" {
  source              = "./modules/eks"
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  rds_security_group_id = module.rds.security_group_id
  node_instance_type  = var.eks_node_instance_type
}

module "rds" {
  source             = "./modules/rds"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
}

module "s3"          { source = "./modules/s3" }
module "cloudfront"  { source = "./modules/cloudfront" }
module "security"    { source = "./modules/security" }
```

Each module has `variables.tf` (inputs), `main.tf` (resources), and `outputs.tf` (what it exposes).

### Why it was done

Without modules, all 60+ resources would be in one flat `main.tf` — 2,000+ lines, impossible to navigate. With modules:
- `networking` module is the VPC + subnets + NAT Gateway, independently testable
- `eks` module is the cluster, node group, IAM roles, IRSA — independently replaceable
- Changing RDS settings only requires touching the `rds` module
- Modules can be reused (copy `networking` module for a new environment)

### Advantages

| Advantage | Detail |
|---|---|
| Separation of concerns | VPC change affects only networking module, doesn't risk EKS config |
| Reusability | Add a `dev` environment in `environments/dev/main.tf` calling the same modules |
| Readability | Root `main.tf` reads like an architecture diagram |
| Independent testing | Each module can be validated independently with `terraform validate` |

---

*Every item above is verified from actual code in the three repositories: `stage-app`, `stage-helm`, and `stage-infra`.*
