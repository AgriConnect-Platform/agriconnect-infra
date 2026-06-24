# AgriConnect — Complete Pipeline & GitOps Explanation

> Every workflow, every line, every concept — from a code push to pods running in Kubernetes.
> GitHub Actions, GitOps, ArgoCD, branch strategy, secrets, protection rules — all of it.

---

## Table of Contents

1. [What is a CI/CD Pipeline?](#1-what-is-a-cicd-pipeline)
2. [What is GitHub Actions?](#2-what-is-github-actions)
3. [The Complete Pipeline Architecture](#3-the-complete-pipeline-architecture)
4. [Branching Strategy](#4-branching-strategy)
5. [Branch Protection Rules](#5-branch-protection-rules)
6. [Secrets — Every Secret Explained](#6-secrets--every-secret-explained)
7. [Pipeline 1: main.yml — The CI Orchestrator](#7-pipeline-1-mainyml--the-ci-orchestrator)
8. [Pipeline 2: ci-auth.yml — Service Build (All 5 Services)](#8-pipeline-2-ci-authyml--service-build-all-5-services)
9. [Pipeline 3: ci-prod.yml — Production Release](#9-pipeline-3-ci-prodyml--production-release)
10. [Pipeline 4: cd-frontend.yml — Frontend Deploy](#10-pipeline-4-cd-frontendyml--frontend-deploy)
11. [Pipeline 5: notify-failure.yml — Alert System](#11-pipeline-5-notify-failureyml--alert-system)
12. [Pipeline 6: infra-terraform.yml — Infrastructure](#12-pipeline-6-infra-terraformyml--infrastructure)
13. [Pipeline 7: bootstrap.yml — One-Time Setup](#13-pipeline-7-bootstrapyml--one-time-setup)
14. [What is GitOps?](#14-what-is-gitops)
15. [ArgoCD — The GitOps Engine](#15-argocd--the-gitops-engine)
16. [The Three-Repo GitOps Model](#16-the-three-repo-gitops-model)
17. [Complete Flow: Code Push to Pod Running](#17-complete-flow-code-push-to-pod-running)
18. [GitHub Actions Concepts Reference](#18-github-actions-concepts-reference)

---

## 1. What is a CI/CD Pipeline?

**CI = Continuous Integration**
Every time a developer pushes code, automated tools:
- Check code quality (lint)
- Scan for security issues
- Build the Docker image
- Run tests
- Verify the application starts correctly

**CD = Continuous Delivery / Deployment**
After CI passes, automated tools:
- Push the built image to a registry
- Update deployment configuration
- Deploy to Kubernetes
- Verify deployment health

**Why pipelines exist:**
Without automation, deploying code means:
1. Developer builds on their laptop
2. Uploads to server manually
3. Restarts the application manually
4. Hopes nothing breaks

With pipelines:
1. Developer pushes code → everything else is automatic
2. Bugs are caught before reaching production
3. Every deployment is identical and reproducible
4. No "works on my machine" problems

---

## 2. What is GitHub Actions?

GitHub Actions is GitHub's built-in CI/CD platform. When you push code, GitHub starts fresh virtual machines (called **runners**) and runs your defined steps on them.

### Key Concepts

**Workflow** — A YAML file in `.github/workflows/`. Defines what to do and when.

**Trigger (`on:`)** — What event starts the workflow. Push, PR, schedule, manual button, another workflow calling it.

**Job** — A group of steps that run on the same runner (VM). Jobs run in parallel by default unless you use `needs:`.

**Step** — A single command or action inside a job.

**Action (`uses:`)** — A pre-built reusable step. `actions/checkout@v4` is maintained by GitHub and checks out your code. You can use community actions or write your own.

**Runner (`runs-on: ubuntu-latest`)** — The virtual machine that executes the job. GitHub provides Ubuntu, Windows, and macOS runners. Each job gets a fresh VM.

**Environment Variables (`env:`)** — Variables available to all steps in a workflow or job.

**Secrets (`${{ secrets.MY_SECRET }}`)** — Encrypted values stored in GitHub. Never visible in logs.

**Outputs (`outputs:`)** — Values a job produces that other jobs can read.

**Artifacts** — Files uploaded from one job and downloaded in another (e.g., the Terraform plan file).

**Matrix (`strategy.matrix`)** — Run the same job multiple times with different parameters. Used in ci-prod.yml to build all 5 services in parallel with different Dockerfiles.

---

## 3. The Complete Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    agriconnect-app repo (dev branch)                 │
│                                                                      │
│  Developer pushes code                                               │
│         ↓                                                            │
│  main.yml triggers                                                   │
│  ┌─────────┐  ┌──────────┐                                          │
│  │ changes │  │  sast    │ ← parallel, SonarCloud                   │
│  └────┬────┘  └────┬─────┘                                          │
│       │            │                                                 │
│       │       ┌────▼─────┐                                          │
│       │       │   snyk   │ ← after sast                             │
│       │       └────┬─────┘                                          │
│       │            │                                                 │
│       │       ┌────▼─────┐                                          │
│       │       │   lint   │ ← after sast+snyk                        │
│       │       └────┬─────┘                                          │
│       │            │                                                 │
│       │    ┌───────┴────────────────────────────┐                   │
│       │    │  ci-auth  ci-market  ci-order  ... │ ← all parallel    │
│       │    │  (build+scan+smoke+push to ECR)    │                   │
│       │    └───────────────────┬────────────────┘                   │
│       │                        │                                     │
│       │               ┌────────▼──────────┐                         │
│       │               │ update-helm-values│ ← updates image tags    │
│       │               └────────┬──────────┘    in helm repo         │
│       │                        │                                     │
│       │                   ┌────▼────┐                               │
│       │                   │ ArgoCD  │ ← watches helm repo           │
│       │                   │  sync   │   deploys to EKS              │
│       │                   └─────────┘                               │
│       │                                                              │
│       └── if frontend changed ──► cd-frontend.yml                   │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                 agriconnect-infra repo (main branch)                 │
│                                                                      │
│  Any terraform/** file changes                                       │
│         ↓                                                            │
│  infra-terraform.yml triggers                                        │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐                        │
│  │  scan    │→ │   plan   │→ │  APPROVAL  │→ terraform apply        │
│  │ (Trivy)  │  │(validate)│  │   (human)  │                         │
│  └──────────┘  └──────────┘  └────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│              agriconnect-app repo (prod branch)                      │
│                                                                      │
│  Push to prod branch                                                 │
│         ↓                                                            │
│  ci-prod.yml triggers                                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐                  │
│  │ APPROVAL │→ │ get-ver  │→ │ build (matrix ×5)│→ update helm prod │
│  └──────────┘  └──────────┘  └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Branching Strategy

You use a **trunk-based development with environment branches** strategy across 3 repos:

### agriconnect-app (application code)

```
main (protected, no direct push)
  ├── dev      ← active development, triggers CI pipeline
  ├── prod     ← production releases, triggers ci-prod.yml
  └── feature/* ← individual developer feature branches (not shown in workflows)
```

| Branch | Purpose | Pipeline Triggered |
|---|---|---|
| `dev` | Integration branch, all dev work merges here | main.yml (CI + deploy to production namespace) |
| `prod` | Stable production releases only | ci-prod.yml (with manual approval) |
| `feature/*` | Individual features in progress | None (push to feature branch doesn't trigger CI) |

**Flow:**
```
Developer creates feature/add-bid-system branch
  → develops locally
  → pushes feature branch (no pipeline)
  → opens Pull Request: feature/add-bid-system → dev
  → branch protection: PR requires 1 review
  → reviewer approves
  → merged to dev → main.yml CI fires
  → if this sprint's changes are ready for production:
  → PR from dev → prod
  → merged to prod → ci-prod.yml fires with approval gate
```

### agriconnect-helm (Kubernetes configuration)

```
dev   ← ArgoCD watches this, deploys to production namespace
prod  ← ArgoCD watches this, deploys to prod namespace
```

The app pipeline updates these branches, not developers directly. CI writes image tags here.

### agriconnect-infra (Terraform)

```
main  ← all Terraform changes go here
       → infra-terraform.yml triggers on every push
```

---

## 5. Branch Protection Rules

Branch protection rules prevent accidental pushes directly to important branches.

### How to Configure in GitHub

`Repository → Settings → Branches → Add rule`

### Recommended Rules for This Project

**For `dev` branch (app repo):**
```
✅ Require a pull request before merging
   ✅ Required number of approvals: 1
✅ Require status checks to pass before merging
   → Add: "Lint - ESLint"
   → Add: "SAST - SonarCloud"
   → Add: "Build, Scan & Push" (for each service)
✅ Require branches to be up to date before merging
✅ Do not allow bypassing the above settings
```

**For `prod` branch (app repo):**
```
✅ Require a pull request before merging
   ✅ Required number of approvals: 2
✅ Require all CI checks to pass
✅ Restrict who can push: only maintainers
✅ Do not allow force pushes
```

**For `main` branch (infra repo):**
```
✅ Require a pull request before merging
✅ Require status checks: "Trivy IaC Scan", "Terraform Plan"
✅ Do not allow force pushes
✅ Require linear history (no merge commits)
```

**Why these rules matter:**
- Without them, anyone can push directly to `prod` or `main` and bypass all CI checks
- Protection ensures every change is reviewed and passes automated checks
- Prevents accidental `git push origin prod` from a developer's laptop

---

## 6. Secrets — Every Secret Explained

Secrets are stored at the **organization level** in `AgriConnect-Platform` GitHub org settings — not per repository. This means all 3 repos automatically share the same secrets.

`Org Settings → Secrets and variables → Actions`

### Every Secret in This Project

| Secret Name | Value | Used In |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key | All pipelines needing AWS |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key | All pipelines needing AWS |
| `TF_VAR_RDS_PASSWORD` | MySQL root password | infra-terraform.yml |
| `TF_VAR_JWT_SECRET` | JWT signing secret | infra-terraform.yml |
| `TF_VAR_SMTP_PASS` | Gmail app password | infra-terraform.yml, notify-failure.yml |
| `GH_PAT` | GitHub Personal Access Token | main.yml, ci-prod.yml (writes to helm repo) |
| `SONAR_TOKEN` | SonarCloud API token | main.yml (SAST) |
| `SNYK_TOKEN` | Snyk API token | main.yml (dependency scan) |

### How Secrets Flow Into Workflows

```yaml
# In the workflow file:
- uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

`${{ secrets.AWS_ACCESS_KEY_ID }}` is a GitHub Actions expression. At runtime, GitHub replaces this with the actual value — but **never prints it in logs**. If you accidentally `echo ${{ secrets.AWS_ACCESS_KEY_ID }}`, GitHub replaces the output with `***`.

### Why `GH_PAT` Is Needed

The `update-helm-values` job in main.yml needs to push code to the `agriconnect-helm` repo. The default `GITHUB_TOKEN` only has permissions for the current repo. A Personal Access Token with `repo` scope can write to other repos.

```yaml
- uses: actions/checkout@v4
  with:
    repository: agriconnect-platform/agriconnect-helm
    token: ${{ secrets.GH_PAT }}   # ← PAT allows cross-repo write
```

### GitHub Environments and Approval Gates

An **Environment** in GitHub is a named deployment target with optional protection rules.

`Repository → Settings → Environments → New environment → "production"`

Configure it:
```
✅ Required reviewers: [your GitHub username]
   (pipeline pauses and emails you for approval before proceeding)
✅ Wait timer: 0 minutes
✅ Deployment branches: selected branches → prod, main
```

In the workflow:
```yaml
apply:
  environment: production   # ← triggers approval requirement
```

When the pipeline reaches this job, it pauses and sends you an email/notification. You go to GitHub, review the plan output from the previous job, and click "Approve" or "Reject." The job only runs after your approval.

---

## 7. Pipeline 1: main.yml — The CI Orchestrator

**File:** `stage-app/.github/workflows/main.yml`
**Triggers:** Push to `dev` branch, or manual (`workflow_dispatch`)
**Purpose:** Runs security scans, lints code, builds all 5 services, updates Helm image tags

```yaml
name: CI Pipeline
```
The display name shown in the GitHub Actions tab.

```yaml
on:
  push:
    branches: [dev]     # fires on every push to dev branch
  workflow_dispatch:    # also has a manual "Run workflow" button in GitHub UI
```

### Job 1: changes — Detect What Changed

```yaml
jobs:
  changes:
    name: Detect changed paths
    runs-on: ubuntu-latest
    outputs:
      frontend: ${{ steps.filter.outputs.frontend }}
```

`outputs:` — this job produces a value called `frontend` that other jobs can read.

```yaml
    steps:
      - uses: actions/checkout@v4
```
Downloads the repo code onto the runner VM.

```yaml
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            frontend:
              - 'frontend/**'
```
`dorny/paths-filter` is a community action that checks which files changed in the push.
`filters:` defines named groups. `frontend: 'frontend/**'` means "the `frontend` flag is true if any file under `frontend/` changed."
`id: filter` gives this step a name so later steps can reference its output.

**Why this exists:** Building and deploying the React frontend takes 3-4 minutes and costs money. If only backend code changed, there's no point rebuilding the frontend. This job sets a flag so the frontend job only runs when frontend files actually changed.

---

### Job 2: sast — SonarCloud Static Analysis

```yaml
  sast:
    name: SAST - SonarCloud
    runs-on: ubuntu-latest
    outputs:
      result: ${{ steps.sonar.outcome }}
```

`outcome` is a built-in property of every step — either `success`, `failure`, `cancelled`, or `skipped`. This output is used later by `notify-security` to know whether to send an alert email.

```yaml
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
```
`fetch-depth: 0` downloads the FULL git history, not just the latest commit. SonarCloud needs this to calculate code coverage trends, blame information, and new vs. existing issues.

```yaml
      - name: SonarCloud Scan
        id: sonar
        uses: SonarSource/sonarcloud-github-action@v3
        continue-on-error: true
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        with:
          args: >-
            -Dsonar.qualitygate.wait=false
```

`SonarSource/sonarcloud-github-action@v3` — official SonarCloud action. Sends code to SonarCloud's servers for analysis.

`continue-on-error: true` — even if SonarCloud finds issues, this step is marked as "passed" and the pipeline continues. SAST findings are reported but don't block deployment here.

`-Dsonar.qualitygate.wait=false` — don't wait for the Quality Gate result. SonarCloud analysis can take 2-3 minutes. With `wait=false`, the step finishes immediately after submitting code. Results appear on SonarCloud's dashboard asynchronously.

`sonar-project.properties` in the repo root tells SonarCloud which files to scan:
```properties
sonar.projectKey=AgriConnect-Platform_agriconnect-app
sonar.organization=agriconnect-platform
sonar.sources=services,shared
sonar.exclusions=**/node_modules/**,shared/scripts/**
```

---

### Job 3: snyk — Dependency Vulnerability Scan

```yaml
  snyk:
    name: Snyk - Dependency Scan
    needs: sast         # waits for sast to complete first
    if: always()        # runs even if sast failed
    runs-on: ubuntu-latest
    outputs:
      result: ${{ steps.snyk-scan.outcome }}
```

`needs: sast` — this job starts only after `sast` finishes. Creates a sequential dependency.
`if: always()` — runs regardless of whether `sast` succeeded or failed. Without this, if `sast` fails, GitHub would skip all jobs that depend on it.

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
```
Sets up Node.js 20 on the runner. Required because Snyk is an npm package.

```yaml
      - name: Install Snyk CLI
        run: npm install -g snyk
```
`-g` installs globally so the `snyk` command is available in PATH.

```yaml
      - name: Install dependencies
        run: |
          for dir in shared services/auth-service services/marketplace-service services/order-service services/media-service services/notification-service; do
            (cd $dir && npm install --omit=dev 2>/dev/null)
          done
```
Snyk needs `node_modules` to exist to analyze dependencies. This loop runs `npm install` in each service directory.
`--omit=dev` — skips devDependencies (not shipped to production, not relevant for security).
`2>/dev/null` — suppresses npm warnings from cluttering the output.
`(cd $dir && ...)` — runs in a subshell so the directory change doesn't affect the main shell.

```yaml
      - name: Run Snyk scan
        id: snyk-scan
        run: snyk test --all-projects --severity-threshold=high
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        continue-on-error: true
```
`--all-projects` — scans all package.json files found in the repo.
`--severity-threshold=high` — only reports HIGH and CRITICAL vulnerabilities (ignores LOW/MEDIUM noise).
`continue-on-error: true` — findings don't block the pipeline. The result is captured in `steps.snyk-scan.outcome` and used for email notification only.

---

### Job 4: notify-security — Send Email on Scan Failure

```yaml
  notify-security:
    name: Notify - Security Scan Failed
    needs: [sast, snyk]
    if: always() && (needs.sast.outputs.result == 'failure' || needs.snyk.outputs.result == 'failure')
    uses: ./.github/workflows/notify-failure.yml
    secrets: inherit
    with:
      scan_name: "${{ needs.sast.outputs.result == 'failure' && needs.snyk.outputs.result == 'failure' && 'SonarCloud SAST + Snyk' || needs.sast.outputs.result == 'failure' && 'SonarCloud SAST' || 'Snyk Dependency Scan' }}"
```

`needs: [sast, snyk]` — waits for both to finish.
`if: always() && (...)` — only runs if at least one scan failed. The `&&` and `||` inside the condition are logic operators on the `outcome` values.
`uses: ./.github/workflows/notify-failure.yml` — calls another workflow file as a "reusable workflow." This is how you avoid copy-pasting the email logic.
`secrets: inherit` — passes all secrets to the called workflow.
`scan_name:` — uses a ternary chain to build the right name: "SonarCloud SAST + Snyk" or "SonarCloud SAST" or "Snyk Dependency Scan" based on which failed.

---

### Job 5: lint — ESLint Code Quality Gate

```yaml
  lint:
    name: Lint - ESLint
    needs: [sast, snyk]     # waits for both security scans to complete
    if: always()             # runs even if scans failed
    runs-on: ubuntu-latest
```

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'

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

`npx eslint@8` — downloads and runs ESLint version 8 without installing it. `npx` fetches packages on-demand.
`services/auth-service` (etc.) — directories to lint. ESLint recursively scans all `.js` files.
`--ext .js` — only lint `.js` files (ignore `.json`, `.md`, etc.)
`--max-warnings 0` — ZERO warnings allowed. Even a single warning fails this step.
The `.eslintrc.json` in the repo root defines the rules: `no-undef: error`, `no-unused-vars: warn`, etc.
`.eslintignore` excludes `shared/scripts/` (seed data, not production code).

**Why lint blocks the builds:** All 5 `ci-*` jobs have `needs: lint`. If lint fails, no Docker images are built. You fix the lint issue first.

---

### Jobs 5-9: ci-auth, ci-marketplace, ci-order, ci-media, ci-notification

```yaml
  ci-auth:
    needs: lint
    uses: ./.github/workflows/ci-auth.yml
    secrets: inherit
```

`uses:` — calls another workflow file. This is the "reusable workflow" pattern. Each service has its own `.github/workflows/ci-*.yml` file with service-specific values (port, ECR repo name, Dockerfile path).

`secrets: inherit` — the called workflow receives all secrets from the parent. Without this, `ci-auth.yml` wouldn't have access to `AWS_ACCESS_KEY_ID`, etc.

All 5 jobs have `needs: lint` so they all wait for lint, then all run in parallel simultaneously. Building 5 Docker images in parallel takes ~5 minutes instead of ~25 minutes sequentially.

---

### Job 10: update-helm-values — Trigger ArgoCD Sync

```yaml
  update-helm-values:
    name: Update image tags in Helm repo
    needs: [ci-auth, ci-marketplace, ci-order, ci-media, ci-notification]
    if: always() && needs.ci-auth.result == 'success' && needs.ci-marketplace.result == 'success' && needs.ci-order.result == 'success' && needs.ci-media.result == 'success' && needs.ci-notification.result == 'success'
```

`needs: [all 5 services]` — waits for ALL five builds to complete.
`if: always() && needs.*.result == 'success'` — only runs if every single service build passed. If even one fails, no Helm update happens. You fix the failing service first.

```yaml
    steps:
      - name: Checkout helm repo
        uses: actions/checkout@v4
        with:
          repository: agriconnect-platform/agriconnect-helm
          token: ${{ secrets.GH_PAT }}     # PAT needed to write to another repo
          ref: dev
          path: helm-repo
```
Checks out the `agriconnect-helm` repo (a different repo!) into a folder called `helm-repo` on the runner. `ref: dev` checks out the dev branch.

```yaml
      - name: Update image tags
        run: |
          SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          sed -i "s/^\( *tag:\) .*/\1 ${SHA}/" helm-repo/helm/agriconnect/values.yaml
```

`github.sha` — the full 40-character git commit SHA of the push that triggered this workflow.
`cut -c1-7` — takes only the first 7 characters. `b93b5a1` instead of `b93b5a1f2c3d4e5f...`
`sed -i` — edits the file in-place.
`"s/^\( *tag:\) .*/\1 ${SHA}/"` — a regex substitution:
  - `^` — start of line
  - `\( *tag:\)` — captures "  tag:" (with any leading spaces)
  - ` .*` — matches the current value after "tag:"
  - `\1 ${SHA}` — replaces with the captured "  tag:" + the new SHA

Result: `  tag: b93b5a1` gets written for every service in values.yaml.

```yaml
      - name: Commit and push
        run: |
          SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          cd helm-repo
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add helm/agriconnect/values.yaml
          git diff --staged --quiet || git commit -m "ci: update image tags to ${SHA} [skip ci]"
          git push origin dev
```

`git config user.name/email` — needed because git requires an identity to commit. Using the `github-actions[bot]` identity is conventional.
`git diff --staged --quiet` — checks if there are actually any changes. If the image tag didn't change (same commit somehow triggered twice), skip the commit.
`|| git commit` — the `||` means "run this if the previous command failed." `git diff --quiet` returns exit code 1 if there ARE changes, so `||` triggers the commit.
`[skip ci]` in the commit message — tells GitHub Actions not to trigger CI on this commit. Without this, pushing to the helm repo would trigger helm's own CI (infinite loop).
`git push origin dev` — pushes the tag update to the helm repo's dev branch. **This is what triggers ArgoCD to sync.**

---

### Job 11: cd-frontend

```yaml
  cd-frontend:
    needs: [changes]
    if: needs.changes.outputs.frontend == 'true'
    uses: ./.github/workflows/cd-frontend.yml
    secrets: inherit
```

`needs.changes.outputs.frontend == 'true'` — reads the output from the `changes` job. Only runs if frontend files changed. If you only pushed backend code, this entire job is skipped.

---

## 8. Pipeline 2: ci-auth.yml — Service Build (All 5 Services)

**File:** `stage-app/.github/workflows/ci-auth.yml`
**Called by:** main.yml (via `uses:`) and ci-prod.yml
**Purpose:** Build, security-scan, smoke-test, and push one service image to ECR

```yaml
name: CI - Auth Service

on:
  workflow_call:    # can only be called by another workflow, not triggered directly
```

`workflow_call` — makes this a reusable workflow. It has no `push:` or `schedule:` trigger. It only runs when another workflow uses `uses: ./.github/workflows/ci-auth.yml`.

```yaml
env:
  AWS_REGION: ap-south-1
  SERVICE:    auth              # used in cache key names
  CONTEXT:    .                # Docker build context = root of repo
  DOCKERFILE: services/auth-service/Dockerfile
  ECR_REPO:   agriconnect-auth
```

These `env:` values at the workflow level are available in every step. This is the only thing that differs between `ci-auth.yml`, `ci-marketplace.yml`, etc. — the `SERVICE`, `DOCKERFILE`, and `ECR_REPO` values.

---

### Step 1: Checkout

```yaml
    steps:
      - uses: actions/checkout@v4
```
Downloads the repo code to the runner. Every job on a fresh VM needs this.

---

### Step 2: Configure AWS Credentials

```yaml
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
```

This action sets AWS environment variables and configures the AWS CLI and SDKs. After this step, any `aws` CLI command works, and the AWS SDK in Node.js/Python automatically picks up these credentials.

Under the hood, it sets:
```
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=ap-south-1
```

---

### Step 3: Login to ECR

```yaml
      - id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2
```

ECR is a private Docker registry — you need to authenticate before pushing. This action:
1. Calls `aws ecr get-login-password` to get a temporary token
2. Runs `docker login` with that token
3. Outputs the registry URL as `steps.login-ecr.outputs.registry`
   = `893431614084.dkr.ecr.ap-south-1.amazonaws.com`

---

### Step 4: Build Image Tag

```yaml
      - name: Set image tag
        id: tag
        run: |
          SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          echo "sha=${SHA}" >> $GITHUB_OUTPUT
          echo "full_image=${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPO }}:${SHA}" >> $GITHUB_OUTPUT
```

`echo "key=value" >> $GITHUB_OUTPUT` — the way to set step outputs in modern GitHub Actions. The `tag` step now has two outputs:
- `steps.tag.outputs.sha` = `b93b5a1`
- `steps.tag.outputs.full_image` = `893431614084.dkr.ecr.ap-south-1.amazonaws.com/agriconnect-auth:b93b5a1`

---

### Step 5: Setup Docker BuildX

```yaml
      - uses: docker/setup-buildx-action@v3
```

BuildX is Docker's extended build system. It enables:
- **Layer caching** (the most important feature here — caches FROM/RUN/COPY layers)
- Multi-platform builds
- Faster builds by reusing unchanged layers from previous runs

---

### Step 6: Build Image (but don't push yet)

```yaml
      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: ${{ env.CONTEXT }}          # . (root of repo)
          file: ${{ env.DOCKERFILE }}           # services/auth-service/Dockerfile
          push: false                           # ← build only, don't push
          load: true                            # ← load into local Docker daemon (for smoke test)
          tags: ${{ steps.tag.outputs.full_image }}
          cache-from: type=gha,scope=${{ env.SERVICE }}   # read from cache
          cache-to: type=gha,mode=max,scope=${{ env.SERVICE }}  # write to cache
```

`push: false` + `load: true` — builds the image and makes it available locally on the runner, but doesn't push to ECR. We need the local image for the smoke test next.

`cache-from/cache-to: type=gha` — GitHub Actions cache. Docker layers are cached between runs. If the `FROM node:20-alpine` layer hasn't changed, it's read from cache (milliseconds). If `package.json` hasn't changed, the `npm install` layer is cached too. Only changed layers are rebuilt.

`scope: ${{ env.SERVICE }}` — each service has its own cache bucket (`auth`, `marketplace`, etc.) so their caches don't collide.

---

### Step 7: Trivy Security Scan

```yaml
      - name: Scan with Trivy
        run: |
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
          trivy image --severity CRITICAL --exit-code 1 --ignore-unfixed ${{ steps.tag.outputs.full_image }}
```

`curl ... | sh` — downloads and installs Trivy on the runner (not pre-installed on ubuntu-latest).

`trivy image` — scans a Docker image for known CVEs (Common Vulnerabilities and Exposures).

`--severity CRITICAL` — only report CRITICAL vulnerabilities (not HIGH/MEDIUM/LOW).

`--exit-code 1` — if any CRITICAL CVE is found, exit with code 1. GitHub Actions treats non-zero exit codes as failures. **This is the security gate** — a CRITICAL vulnerability fails the entire pipeline and nothing gets pushed to ECR.

`--ignore-unfixed` — skip CVEs that don't have a fix yet. No point blocking deployment for issues you can't fix.

**What Trivy checks:**
- OS packages (Alpine `apk` packages)
- Language packages (`node_modules` in the image)
- Compares against NVD (National Vulnerability Database) + GitHub Advisory Database

---

### Step 8: Smoke Test

```yaml
      - name: Smoke test — verify /healthz responds
        run: |
          docker run -d \
            -e PORT=3001 \
            -e SKIP_DB=true \
            -p 3001:3001 \
            --name smoke-${{ env.SERVICE }} \
            ${{ steps.tag.outputs.full_image }}
```

`docker run -d` — starts the container in detached mode (background).
`-e PORT=3001` — passes an environment variable to the container.
`-e SKIP_DB=true` — tells the Node.js service to skip database connection on startup. The runner has no RDS access. The service should handle this gracefully.
`-p 3001:3001` — maps runner port 3001 to container port 3001.
`--name smoke-auth` — gives the container a name for easy reference.

```yaml
          echo "Waiting for /healthz..."
          for i in $(seq 1 20); do
            RESP=$(curl -sf http://localhost:3001/healthz 2>/dev/null || true)
            if [ -n "$RESP" ]; then
              echo "$RESP"
              echo "Smoke test passed!"
              docker rm -f smoke-${{ env.SERVICE }} || true
              exit 0
            fi
            sleep 1
          done
          echo "FAILED: /healthz did not respond in 20s"
          docker logs smoke-${{ env.SERVICE }} 2>/dev/null || true
          docker rm -f smoke-${{ env.SERVICE }} || true
          exit 1
```

`seq 1 20` — loops 20 times (20 seconds max wait).
`curl -sf` — `-s` silent (no progress bar), `-f` fail silently on HTTP errors (returns empty string instead of error HTML).
`2>/dev/null` — suppresses curl's error messages during the waiting period.
`|| true` — prevents the `set -e` shell from exiting on curl failure.
`if [ -n "$RESP" ]` — checks if the response is non-empty (curl returned something).
`docker rm -f` — removes the container (cleanup).
`exit 0` — explicit success.

If the container doesn't respond in 20 seconds:
`docker logs smoke-auth` — prints the container logs to help debug why it failed.
`exit 1` — fails the step, fails the job, fails the pipeline. **Nothing gets pushed to ECR.**

---

### Step 9: Push to ECR

```yaml
      - name: Push to ECR
        uses: docker/build-push-action@v5
        with:
          context: ${{ env.CONTEXT }}
          file: ${{ env.DOCKERFILE }}
          push: true                  # ← now push
          tags: |
            ${{ steps.tag.outputs.full_image }}                              # :b93b5a1
            ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPO }}:latest  # :latest
          cache-from: type=gha,scope=${{ env.SERVICE }}
```

Builds again (from cache, very fast) and pushes both tags:
- `:b93b5a1` — permanent, immutable reference to this exact build
- `:latest` — always points to the newest image

**Why two tags?** ArgoCD deploys using the SHA tag (specific, traceable). The `latest` tag is useful for manually pulling the newest image for debugging.

---

## 9. Pipeline 3: ci-prod.yml — Production Release

**File:** `stage-app/.github/workflows/ci-prod.yml`
**Triggers:** Push to `prod` branch
**Purpose:** Production deployment with version tagging, manual approval, and matrix builds

```yaml
on:
  push:
    branches: [prod]
  workflow_dispatch:
```

### Job 1: approval — Manual Gate First

```yaml
  approval:
    name: Await Production Approval
    runs-on: ubuntu-latest
    environment: production    # ← triggers GitHub approval requirement
    steps:
      - run: echo "Production deployment approved"
```

This is the very first job and **every other job depends on it**. The pipeline pauses here. A required reviewer gets notified. Only after they approve does anything else run.

The job itself does nothing (`echo "Production deployment approved"`) — the approval is the entire purpose.

### Job 2: get-version — Git Tag Based Versioning

```yaml
  get-version:
    needs: approval
    outputs:
      version: ${{ steps.version.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0    # need full history to read git tags
      - name: Get version from git tag
        id: version
        run: |
          TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0")
          echo "tag=$TAG" >> $GITHUB_OUTPUT
```

`git describe --tags --abbrev=0` — finds the most recent git tag (e.g., `v1.2.0`).
`2>/dev/null || echo "v1.0.0"` — if no tags exist, default to `v1.0.0`.

**How to create a version tag:**
```bash
git tag v1.2.0
git push origin v1.2.0
# then push to prod branch to trigger ci-prod.yml
```

### Job 3: build — Matrix Strategy

```yaml
  build:
    name: Build & Push - ${{ matrix.service }}
    needs: get-version
    strategy:
      matrix:
        include:
          - service: auth
            dockerfile: services/auth-service/Dockerfile
            ecr_repo: agriconnect-auth
          - service: marketplace
            dockerfile: services/marketplace-service/Dockerfile
            ecr_repo: agriconnect-marketplace
          # ... 3 more
```

`strategy.matrix` — runs this job 5 times in parallel, once per `include` entry. Each run gets different values for `matrix.service`, `matrix.dockerfile`, `matrix.ecr_repo`.

The job name becomes `Build & Push - auth`, `Build & Push - marketplace`, etc.

```yaml
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/${{ matrix.ecr_repo }}:${{ needs.get-version.outputs.version }}
            ${{ steps.login-ecr.outputs.registry }}/${{ matrix.ecr_repo }}:stable
```

Two tags: `:v1.2.0` (version) and `:stable` (always the latest stable release).

### Job 4: update-helm-prod — Deploy to Production Namespace

```yaml
  update-helm-prod:
    needs: [get-version, build]
    steps:
      - uses: actions/checkout@v4
        with:
          repository: agriconnect-platform/agriconnect-helm
          token: ${{ secrets.GH_PAT }}
          ref: prod         # ← prod branch of helm repo
          path: helm-repo

      - name: Update image tags to version
        run: |
          VERSION=${{ needs.get-version.outputs.version }}
          sed -i "s/^\( *tag:\) .*/\1 ${VERSION}/" helm-repo/helm/agriconnect/values.yaml

      - name: Commit and push to prod branch
        run: |
          git commit -m "ci: deploy ${VERSION} to production [skip ci]"
          git push origin prod    # ← ArgoCD watches prod branch → deploys to prod namespace
```

ArgoCD has a separate application (`agriconnect-prod`) watching the helm repo's `prod` branch. When this job pushes to `prod`, ArgoCD syncs to the `prod` Kubernetes namespace using `values-prod.yaml` (2 replicas, larger resources).

---

## 10. Pipeline 4: cd-frontend.yml — Frontend Deploy

**File:** `stage-app/.github/workflows/cd-frontend.yml`
**Called by:** main.yml (when frontend files change)
**Purpose:** Build React app with real API URLs from SSM, upload to S3, invalidate CloudFront

```yaml
on:
  workflow_call:        # called by main.yml
  workflow_dispatch:    # also has manual trigger button
```

```yaml
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-south-1

      - uses: actions/setup-node@v4
        with:
          node-version: '22'      # frontend uses Node 22 (newer than services which use 20)
```

```yaml
      - name: Read API URLs from SSM
        run: |
          FARMBOT_URL=$(aws ssm get-parameter \
            --name /agriconnect/farmbot_api_url \
            --query Parameter.Value \
            --output text)
          BUYERBOT_URL=$(aws ssm get-parameter \
            --name /agriconnect/buyerbot_api_url \
            --query Parameter.Value \
            --output text)
          echo "VITE_FARMBOT_API_URL=$FARMBOT_URL" >> $GITHUB_ENV
          echo "VITE_BUYERBOT_API_URL=$BUYERBOT_URL" >> $GITHUB_ENV
```

`aws ssm get-parameter` — reads a value from AWS SSM Parameter Store.
`--query Parameter.Value` — extracts just the value from the JSON response.
`--output text` — returns plain text instead of quoted JSON string.
`echo "KEY=VALUE" >> $GITHUB_ENV` — sets an environment variable for ALL subsequent steps in the job. After this, every step can use `$VITE_FARMBOT_API_URL`.

```yaml
      - name: Install and build
        run: |
          cd frontend
          npm install
          npm run build
```

`npm run build` triggers Vite. Vite reads `VITE_*` environment variables and bakes them into the JavaScript bundle at build time.

```yaml
      - name: Read deployment config from SSM
        run: |
          BUCKET=$(aws ssm get-parameter \
            --name /agriconnect/frontend-bucket \
            --query Parameter.Value --output text)
          CF_ID=$(aws ssm get-parameter \
            --name /agriconnect/cloudfront-distribution-id \
            --query Parameter.Value --output text)
          echo "BUCKET=$BUCKET" >> $GITHUB_ENV
          echo "CF_ID=$CF_ID" >> $GITHUB_ENV
```

```yaml
      - name: Deploy to S3
        run: |
          aws s3 sync frontend/dist/ s3://${{ env.BUCKET }}/ \
            --delete \
            --cache-control "max-age=31536000,public,immutable"
```

`aws s3 sync` — compares local files with S3 and only uploads changed files.
`--delete` — removes files in S3 that no longer exist locally (cleanup old builds).
`--cache-control "max-age=31536000,public,immutable"` — tells browsers (and CloudFront) to cache these files for 1 year. Safe because Vite generates hashed filenames (`index.a3f2c1.js`) — same content = same hash = same filename. New build = new hash = new filename = cache miss = fresh file.

```yaml
      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ env.CF_ID }} \
            --paths "/*"
```

CloudFront caches files at edge locations worldwide. After uploading new files to S3, CloudFront still serves old cached versions until they expire. This invalidation tells every CloudFront edge location worldwide: "throw away your cached copies of everything." Takes 30-60 seconds to propagate globally.

`"/*"` — invalidates all paths. More targeted would be `"/index.html"` + specific changed asset files, but `/*` is simpler.

---

## 11. Pipeline 5: notify-failure.yml — Alert System

**File:** `stage-app/.github/workflows/notify-failure.yml`
**Called by:** main.yml (when sast or snyk fails)

```yaml
on:
  workflow_call:
    inputs:
      scan_name:
        required: true
        type: string        # accepts a string input from the caller
    secrets:
      TF_VAR_SMTP_PASS:
        required: true      # caller must pass this secret explicitly
```

`inputs:` — reusable workflows can accept typed inputs. `scan_name` is passed from main.yml's `with: scan_name: "..."`.

```yaml
    steps:
      - name: Send failure notification
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: smtp.gmail.com
          server_port: 587
          secure: false
          username: asadchamp109@gmail.com
          password: ${{ secrets.TF_VAR_SMTP_PASS }}
          subject: "❌ AgriConnect CI — ${{ inputs.scan_name }} FAILED"
          to: asadchamp109@gmail.com
          from: AgriConnect CI <asadchamp109@gmail.com>
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

`dawidd6/action-send-mail@v3` — community action that sends email via SMTP.
`secure: false` with port `587` — uses STARTTLS (not SSL). Port 587 starts unencrypted then upgrades to TLS. Port 465 would use SSL from the start (`secure: true`).
`${{ github.ref_name }}` — the branch name (e.g., `dev`)
`${{ github.sha }}` — the commit hash
`${{ github.actor }}` — who triggered the workflow (GitHub username)
`${{ github.run_number }}` — sequential run number for this workflow
`${{ github.run_id }}` — unique ID for this specific run (used in the URL)

---

## 12. Pipeline 6: infra-terraform.yml — Infrastructure

**File:** `stage-infra/.github/workflows/infra-terraform.yml`
**Triggers:** Any change to `terraform/**` files on `main` branch
**Purpose:** Validate, plan, and apply Terraform infrastructure changes

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'    # ← only fires if terraform files changed
  workflow_dispatch:
```

`paths:` — GitHub compares the changed files list with this pattern. If you push a README change, the pipeline doesn't fire. Only Terraform file changes trigger it.

---

### Job 1: scan — Trivy IaC Scan

```yaml
  scan:
    name: Trivy IaC Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Trivy
        run: |
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
      - name: Scan terraform for misconfigurations
        run: trivy config terraform/ --severity CRITICAL,HIGH --exit-code 0 --format table
```

`trivy config` — scans Terraform/Kubernetes YAML/Helm files for misconfigurations (not CVEs).

Examples of what it catches:
- S3 bucket with public access enabled
- Security group with `0.0.0.0/0` ingress on port 22
- RDS with `publicly_accessible = true`
- No encryption on EBS volumes

`--exit-code 0` — findings are REPORTED but don't fail the pipeline. Unlike container scanning where CRITICAL fails the build, IaC misconfigurations are advisory here (some are intentional, like the public S3 bucket for the frontend).

`--format table` — outputs a readable table instead of JSON.

---

### Job 2: plan — Terraform Validate, Format, Plan

```yaml
  plan:
    name: Terraform Plan
    needs: scan
    runs-on: ubuntu-latest
```

```yaml
      - uses: hashicorp/setup-terraform@v3
```
Downloads and installs Terraform on the runner. Without a `version:` pin, it installs the latest stable Terraform version (currently 1.10+). This is why we use `use_lockfile` instead of the deprecated `dynamodb_table`.

```yaml
      - name: Terraform Init
        working-directory: terraform
        run: terraform init
```

`working-directory: terraform` — runs the command from the `terraform/` subdirectory. Equivalent to `cd terraform && terraform init`.

`terraform init` does three things:
1. Reads `versions.tf` backend config → connects to S3 remote state
2. Downloads provider plugins (AWS provider ~5.0, archive ~2.0) into `.terraform/`
3. Downloads any remote modules

```yaml
      - name: Terraform Format Check
        working-directory: terraform
        run: terraform fmt -check -recursive
```

`terraform fmt` normally reformats files. With `-check`, it only checks and exits 1 if any file is not properly formatted. This enforces consistent code style — tabs vs spaces, alignment, etc.

`-recursive` — checks all `.tf` files in subdirectories (modules too).

```yaml
      - name: Terraform Validate
        working-directory: terraform
        run: terraform validate
```

Checks HCL syntax and internal consistency — catches:
- Misspelled resource types
- Missing required arguments
- Wrong variable types
- References to undefined variables

Does NOT call AWS APIs — purely local check.

```yaml
      - name: Terraform Plan
        working-directory: terraform
        env:
          TF_VAR_rds_password: ${{ secrets.TF_VAR_RDS_PASSWORD }}
          TF_VAR_jwt_secret:   ${{ secrets.TF_VAR_JWT_SECRET }}
          TF_VAR_smtp_pass:    ${{ secrets.TF_VAR_SMTP_PASS }}
        run: terraform plan -var-file=terraform.tfvars -out=tfplan
```

`TF_VAR_*` environment variables — Terraform automatically reads env vars prefixed with `TF_VAR_` as variable values. This passes secrets without writing them to any file.

`-var-file=terraform.tfvars` — loads non-secret variables from the committed tfvars file.

`-out=tfplan` — saves the plan to a binary file. The plan contains the exact set of changes to make. Using a saved plan ensures the `apply` job applies exactly what was planned — not a new plan that might have drifted.

```yaml
      - name: Upload plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: |
            terraform/tfplan
            terraform/lambda_package.zip
            terraform/farmbot_package.zip
            terraform/buyerbot_package.zip
          retention-days: 1
```

`actions/upload-artifact@v4` — uploads files from the runner to GitHub's artifact storage. The `apply` job runs on a **different runner** (different VM, fresh disk) and needs these files.

`retention-days: 1` — artifacts are only kept for 1 day. After that, GitHub deletes them to save storage. Since plan → apply must happen within 1 day, this is fine.

Lambda zip files are also uploaded because `terraform apply` needs them to upload Lambda code to AWS.

---

### Job 3: apply — Manual Approval + Apply

```yaml
  apply:
    name: Terraform Apply
    needs: plan
    runs-on: ubuntu-latest
    environment: production   # ← PAUSES for human approval
```

When this job starts, GitHub sees `environment: production`. It checks the environment's protection rules (required reviewers). The pipeline PAUSES and sends a notification to the required reviewer. The reviewer goes to GitHub, sees the link to the plan output, reviews it, and clicks Approve or Reject.

```yaml
      - name: Download plan artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: terraform
```

Downloads the plan file from the `plan` job's artifact. This ensures `apply` uses the EXACT same plan that was reviewed and approved — not a freshly generated plan that might differ.

```yaml
      - name: Terraform Apply
        working-directory: terraform
        env:
          TF_VAR_rds_password: ${{ secrets.TF_VAR_RDS_PASSWORD }}
          TF_VAR_jwt_secret:   ${{ secrets.TF_VAR_JWT_SECRET }}
          TF_VAR_smtp_pass:    ${{ secrets.TF_VAR_SMTP_PASS }}
        run: terraform apply tfplan
```

`terraform apply tfplan` — applies the pre-computed plan file. No interactive prompts. No `-auto-approve` needed because the plan file contains the pre-approved changes.

---

## 13. Pipeline 7: bootstrap.yml — One-Time Setup

**File:** `stage-infra/.github/workflows/bootstrap.yml`
**Triggers:** Manual only (`workflow_dispatch`)
**Purpose:** After fresh `terraform apply`, set up EKS cluster — install LB controller, ArgoCD, run DB migrations, configure CloudFront

This pipeline runs ONCE after a fresh infrastructure deployment. It's the "Day 1" automation.

### Key Steps Explained

**Verify ECR images exist:**
```bash
for svc in auth marketplace order media notification; do
  COUNT=$(aws ecr list-images --repository-name agriconnect-$svc ...)
  if [ "$COUNT" = "0" ]; then exit 1; fi
done
```
Fails fast if images haven't been pushed yet. No point proceeding if there's nothing to deploy.

**Read SSM parameters:**
```bash
CLUSTER=$(aws ssm get-parameter --name /agriconnect/eks-cluster-name ...)
echo "CLUSTER=$CLUSTER" >> $GITHUB_ENV
```
Reads all values Terraform stored in SSM (cluster name, IRSA roles, subnet IDs) and sets them as environment variables for subsequent steps.

**Configure kubectl:**
```bash
aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
```
Generates a `~/.kube/config` file so `kubectl` commands work against the EKS cluster.

**Install AWS Load Balancer Controller:**
```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER \
  --wait --timeout=5m
```
The LB Controller is a Kubernetes operator that watches for `Ingress` resources and automatically creates/configures AWS Application Load Balancers. Without this, the Helm chart's ingress.yaml doesn't create an actual ALB.

**Install ArgoCD:**
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```
Installs ArgoCD into the `argocd` namespace. `kubectl wait` blocks until ArgoCD is actually ready before continuing.

**Apply ArgoCD Applications:**
Two ArgoCD Application manifests are applied (inline YAML):
1. `agriconnect` — watches helm repo's `dev` branch → deploys to `production` namespace
2. `agriconnect-prod` — watches helm repo's `prod` branch → deploys to `prod` namespace

**Run DB migration:**
```bash
kubectl apply -f - <<EOF
kind: Pod
spec:
  containers:
  - command: ["node", "/app/shared/scripts/migrate.js"]
EOF
```
Creates a one-off pod using the `auth-service` image to run database migrations (create tables). Polls the pod until it succeeds or fails.

**Run DB seed:**
Same pattern but runs `seed.js` to populate initial demo data.

**Update CloudFront origin:**
A Python script updates the CloudFront distribution to point at the newly created ALB URL:
```python
cf.update_distribution(Id=cf_id, DistributionConfig=cfg, IfMatch=etag)
```

**Update Lambda environment variables:**
The `weather-alert-processor` and `buyerbot-chatbot` Lambda functions need the ALB URL to call your microservices. This step updates their environment variables with the real ALB DNS.

---

## 14. What is GitOps?

**GitOps = Git as the single source of truth for your infrastructure state.**

In traditional CD (push-based):
```
CI pipeline builds image → pipeline runs kubectl apply → pods updated
```

In GitOps (pull-based):
```
CI pipeline builds image → updates a config file in Git
                           ↓
                    ArgoCD (inside cluster) watches Git
                    notices the config file changed
                    pulls the new config
                    applies it to Kubernetes
```

### Why GitOps is better

| Concern | Traditional CD | GitOps |
|---|---|---|
| Who has cluster access? | CI runner + developers | Only ArgoCD (inside cluster) |
| How do you audit changes? | Pipeline logs | Git commits — full history |
| What if cluster drifts from config? | Nobody notices | ArgoCD detects and self-heals |
| Roll back a bad deploy? | Rerun old pipeline | `git revert` → ArgoCD syncs |
| What's currently deployed? | Check the cluster | Read the Git repo |

**Key principle:** You NEVER run `kubectl apply` manually in production. You update the Git config. ArgoCD handles the rest.

### The Three Sources of Truth

```
agriconnect-app (dev branch)   → application code
agriconnect-helm (dev branch)  → desired Kubernetes state
cluster (production namespace) → actual running state

ArgoCD's job: keep cluster state = helm repo state
```

---

## 15. ArgoCD — The GitOps Engine

ArgoCD runs inside your EKS cluster as a set of pods in the `argocd` namespace. It continuously:
1. Polls the `agriconnect-helm` GitHub repo every 3 minutes
2. Compares what's in Git with what's running in the cluster
3. If they differ (OutOfSync), applies the Git version to the cluster

### ArgoCD Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agriconnect
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/AgriConnect-Platform/agriconnect-helm.git
    targetRevision: dev          # watches the dev branch
    path: helm/agriconnect       # Helm chart is in this directory
    helm:
      valueFiles:
        - values.yaml            # use this values file
      parameters:
        - name: global.irsaRoleArn
          value: "arn:aws:iam::893431614084:role/..."   # injected at bootstrap time
        - name: ingress.subnets
          value: "subnet-abc,subnet-xyz"
  
  destination:
    server: https://kubernetes.default.svc    # the same cluster ArgoCD is running in
    namespace: production                      # deploy to production namespace
  
  syncPolicy:
    automated:
      prune: true       # delete resources that are in cluster but not in Git
      selfHeal: true    # if someone manually changes cluster state, revert to Git
    syncOptions:
      - CreateNamespace=true    # create namespace if it doesn't exist
      - ServerSideApply=true    # use server-side apply (handles large resources better)
```

### `prune: true` Explained

If you remove a service from values.yaml (e.g., delete `media-service`), ArgoCD will:
1. Notice the Helm chart no longer includes `media-service` Deployment, Service, HPA
2. With `prune: true` — delete those resources from the cluster
3. Without `prune: true` — leave orphaned resources running forever

### `selfHeal: true` Explained

If someone runs `kubectl scale deployment auth-service --replicas=0` manually:
1. ArgoCD detects the cluster state (0 replicas) differs from Git (2 replicas)
2. With `selfHeal: true` — ArgoCD reverts it back to 2 replicas
3. Without `selfHeal: true` — the change sticks until the next sync

This enforces the rule: **Git is the only way to change production.**

### Two ArgoCD Applications

**App 1: `agriconnect`**
- Watches: helm repo `dev` branch
- Deploys to: `production` namespace
- Values file: `values.yaml` (2 replicas, standard resources)
- Triggered by: every `git push` to helm dev branch (from CI)

**App 2: `agriconnect-prod`**
- Watches: helm repo `prod` branch
- Deploys to: `prod` namespace
- Values file: `values-prod.yaml` (2 replicas, potentially larger resources)
- Triggered by: ci-prod.yml pushing a version tag to helm prod branch

---

## 16. The Three-Repo GitOps Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Repo 1: agriconnect-app                                                 │
│  Contains: Node.js service code, Dockerfiles, GitHub Actions workflows   │
│  Branch: dev                                                             │
│  CI does: lint → scan → build → push to ECR → update helm repo         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │  (CI writes image tag to)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Repo 2: agriconnect-helm                                                │
│  Contains: Helm chart, values.yaml, ArgoCD application manifests        │
│  Branch: dev (for staging/production), prod (for prod namespace)        │
│  Managed by: CI pipelines (writes image tags), never by hand in prod   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │  (ArgoCD watches and pulls)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Repo 3: agriconnect-infra                                               │
│  Contains: Terraform code, Lambda source, bootstrap workflow            │
│  Branch: main                                                            │
│  CI does: IaC scan → validate → plan → (approval) → apply              │
└─────────────────────────────────────────────────────────────────────────┘
                                 │  (Terraform creates)
                                 ▼
                     EKS Cluster + all AWS resources
```

**Why 3 separate repos?**

| Reason | Explanation |
|---|---|
| Different access controls | Infra repo only senior engineers can merge. App repo all developers can merge. |
| Different change frequency | App changes daily. Infra changes monthly. Helm changes are automated. |
| Auditability | "What deployed to production at 3pm Tuesday?" — look at helm repo git log |
| Security | ArgoCD only needs read access to helm repo. No credentials for app or infra repos. |
| Rollback isolation | Roll back app without touching infra. Roll back Helm config without rebuilding Docker images. |

---

## 17. Complete Flow: Code Push to Pod Running

Here's the FULL end-to-end flow when you fix a bug in auth-service and push to dev:

```
1. Developer pushes commit b93b5a1 to dev branch of agriconnect-app

2. GitHub detects push → triggers main.yml

3. Runner VM starts (fresh Ubuntu VM, nothing installed)

4. Job: changes — checks what files changed
   → backend code changed, frontend not changed
   → sets output: frontend=false

5. Job: sast — SonarCloud analyzes JS code (runs in parallel with step 4)
   → finds 0 new security issues
   → result: success

6. Job: snyk — dependency scan (waits for sast)
   → scans node_modules for CVEs
   → finds nothing high/critical
   → result: success

7. Job: lint — ESLint (waits for sast + snyk)
   → scans all 5 service directories
   → 0 errors, 0 warnings
   → result: success

8. Jobs: ci-auth, ci-marketplace, ci-order, ci-media, ci-notification
   ALL START IN PARALLEL (all need: lint to have passed)

   For ci-auth (and same for other 4):
   a. Fresh runner VM starts
   b. Checks out code
   c. Logs into ECR
   d. Setup Docker BuildX with layer caching
   e. docker build --no-push (loads locally)
      → Stage 1 (builder): npm install, compile
      → Stage 2 (runtime): copy built files, set USER appuser
      → Cache hit on FROM node:20-alpine (unchanged)
      → Cache hit on npm install (package.json unchanged)
      → Only changed files are rebuilt
      → Build takes ~45 seconds (mostly from cache)
   f. Trivy scans the built image
      → checks Alpine packages + node_modules
      → 0 CRITICAL CVEs
      → exit code 0 → passes
   g. Smoke test:
      → docker run -e SKIP_DB=true -p 3001:3001 ...
      → waits up to 20s for /healthz
      → auth-service starts, responds: {"status":"ok"}
      → smoke test passed!
   h. docker push to ECR:
      → uploads agriconnect-auth:b93b5a1
      → uploads agriconnect-auth:latest

9. All 5 ci-* jobs complete successfully (~5 minutes)

10. Job: update-helm-values starts
    a. Checks out agriconnect-helm repo (dev branch)
    b. Updates values.yaml:
       - auth: { tag: b93b5a1 }
       - marketplace: { tag: b93b5a1 }
       - order: { tag: b93b5a1 }
       - media: { tag: b93b5a1 }
       - notification: { tag: b93b5a1 }
    c. git commit -m "ci: update image tags to b93b5a1 [skip ci]"
    d. git push origin dev

11. Total CI time: ~8 minutes

12. ArgoCD polling cycle (~3 minutes after the push):
    a. ArgoCD polls agriconnect-helm repo
    b. Detects: values.yaml changed, tag changed from a1b2c3d to b93b5a1
    c. Status changes to: OutOfSync
    d. Automated sync starts

13. ArgoCD renders Helm chart:
    helm template agriconnect helm/agriconnect \
      -f values.yaml \
      --set global.irsaRoleArn=...
    
    This produces Kubernetes YAML with the new image tag

14. ArgoCD applies the changes:
    kubectl apply -f rendered-manifests/

    Kubernetes sees the auth-service Deployment has changed image:
    old: agriconnect-auth:a1b2c3d
    new: agriconnect-auth:b93b5a1

15. Kubernetes performs rolling update:
    a. Starts a new pod with agriconnect-auth:b93b5a1
    b. Waits for /healthz to return 200 (readiness probe passes)
    c. Starts routing traffic to the new pod
    d. Terminates one old pod (agriconnect-auth:a1b2c3d)
    e. Starts another new pod
    f. Old pod terminates
    → At all times, at least 1 pod is serving traffic (zero downtime)

16. ArgoCD status: Synced + Healthy

Total time from push to live in production: ~10-12 minutes
Zero downtime. Zero manual steps.
```

---

## 18. GitHub Actions Concepts Reference

### `${{ }}` Expressions

GitHub Actions has its own expression language:

| Expression | Value |
|---|---|
| `${{ github.sha }}` | Full 40-char commit hash |
| `${{ github.ref_name }}` | Branch name (e.g., `dev`) |
| `${{ github.actor }}` | Who pushed (GitHub username) |
| `${{ github.run_number }}` | Sequential run number |
| `${{ github.run_id }}` | Unique run identifier |
| `${{ github.repository }}` | `AgriConnect-Platform/agriconnect-app` |
| `${{ secrets.MY_SECRET }}` | Secret value (masked in logs) |
| `${{ needs.job_name.outputs.key }}` | Output from another job |
| `${{ steps.step_id.outputs.key }}` | Output from a step in the same job |
| `${{ steps.step_id.outcome }}` | `success`, `failure`, `cancelled`, `skipped` |
| `${{ env.MY_VAR }}` | Env var set for the workflow |
| `${{ matrix.service }}` | Current matrix value |
| `${{ inputs.param_name }}` | Input to reusable workflow |

### Conditional Execution

```yaml
if: always()                    # run even if previous jobs failed
if: failure()                   # only run if previous job failed
if: success()                   # only run if previous job succeeded (default)
if: needs.job.result == 'success'    # specific job result check
if: github.ref_name == 'prod'   # only on prod branch
if: needs.changes.outputs.frontend == 'true'  # conditional on output
```

### Environment Variable Scopes

```yaml
env:            # workflow-level: available in all jobs
  REGION: ap-south-1

jobs:
  build:
    env:        # job-level: available in all steps of this job
      SERVICE: auth
    steps:
      - name: My step
        env:    # step-level: only available in this step
          TEMP: value
        run: echo $REGION $SERVICE $TEMP
```

### `$GITHUB_ENV` vs `$GITHUB_OUTPUT`

```bash
# Set env var for SUBSEQUENT steps in same job:
echo "MY_VAR=value" >> $GITHUB_ENV

# Set output for OTHER JOBS to read:
echo "my_key=value" >> $GITHUB_OUTPUT
```

`$GITHUB_ENV` — modifies the environment for all later steps in the same job.
`$GITHUB_OUTPUT` — makes a value available to other jobs via `${{ needs.job_name.outputs.key }}`.

### `workflow_call` vs `workflow_dispatch` vs `push`

| Trigger | When it fires |
|---|---|
| `workflow_call` | When another workflow uses `uses:` to call it |
| `workflow_dispatch` | When someone clicks "Run workflow" in GitHub UI |
| `push` | When code is pushed to the repo |
| `schedule` | On a cron schedule |
| `pull_request` | When a PR is opened/updated |

### Caching in GitHub Actions

```yaml
cache-from: type=gha,scope=auth   # read layers from cache
cache-to: type=gha,mode=max,scope=auth  # write layers to cache
```

`type=gha` — GitHub Actions Cache. Stored per repo, max 10GB total.
`scope=auth` — separate cache key per service so they don't overwrite each other.
`mode=max` — cache ALL layers, including intermediate ones.

Without caching: `docker build` takes ~5 minutes (npm install downloads all packages).
With caching: ~30-45 seconds (npm install layer is cached, only changed files rebuilt).

---

*Every pipeline described here exists and runs in your GitHub organization at `github.com/AgriConnect-Platform`.*
