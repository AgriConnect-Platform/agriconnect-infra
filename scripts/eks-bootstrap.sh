#!/bin/bash
# Run this script ONCE after terraform apply to finish EKS setup.
set -e

CLUSTER_NAME="agriconnect-dev-eks"
REGION="ap-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "========================================================"
echo "  AgriConnect EKS Bootstrap"
echo "  Cluster  : $CLUSTER_NAME"
echo "  Region   : $REGION"
echo "  Account  : $ACCOUNT_ID"
echo "  ECR      : $ECR_REGISTRY"
echo "========================================================"

# ── 1. Configure kubectl ──────────────────────────────────────────────────────
echo ""
echo "[1/6] Configuring kubectl..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl get nodes
echo "  kubectl configured."

# ── 2. Install AWS Load Balancer Controller ───────────────────────────────────
echo ""
echo "[2/6] Installing AWS Load Balancer Controller..."

LB_ROLE_ARN=$(aws iam list-roles \
  --query "Roles[?RoleName=='agriconnect-dev-eks-lb-controller-role'].Arn" \
  --output text)
echo "  LB Controller role ARN: $LB_ROLE_ARN"

helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update

# Install without --wait so we don't hang; we'll poll pods below
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "  VPC ID: $VPC_ID"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$LB_ROLE_ARN" \
  --set vpcId="$VPC_ID" \
  --set region="$REGION"

echo "  Helm install submitted. Waiting for LB controller pods to be Ready..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=5m
echo "  AWS Load Balancer Controller is Ready."

# ── 3. Install metrics-server (required for HPA) ─────────────────────────────
# Must come AFTER LB controller is ready — LB webhook blocks Service creation
# if its pod has no endpoints yet.
echo ""
echo "[3/6] Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
echo "  metrics-server applied."

# ── 4. Get IRSA role for services ─────────────────────────────────────────────
echo ""
echo "[4/6] Getting services IRSA role ARN..."
SERVICES_ROLE_ARN=$(aws iam list-roles \
  --query "Roles[?RoleName=='agriconnect-dev-eks-services-role'].Arn" \
  --output text)
echo "  Services IRSA role ARN: $SERVICES_ROLE_ARN"

# ── 5. Deploy app with Helm ───────────────────────────────────────────────────
echo ""
echo "[5/6] Deploying AgriConnect services via Helm..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../helm/agriconnect"

helm upgrade --install agriconnect "$CHART_DIR" \
  --namespace default \
  --set "global.irsaRoleArn=$SERVICES_ROLE_ARN" \
  --set "global.ecrRegistry=$ECR_REGISTRY" \
  --wait --timeout 10m

echo "  Helm deployment complete."

# ── 6. Get ALB DNS ────────────────────────────────────────────────────────────
echo ""
echo "[6/6] Fetching ALB DNS name (up to 3 min)..."

ALB_DNS=""
for i in $(seq 1 18); do
  ALB_DNS=$(kubectl get ingress agriconnect-ingress -n default \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$ALB_DNS" ]; then
    break
  fi
  echo "  Waiting... ($((i * 10))s)"
  sleep 10
done

echo ""
echo "========================================================"
echo "  Bootstrap Complete!"
echo ""
echo "  ALB DNS  : ${ALB_DNS:-<not yet assigned — check: kubectl get ingress>}"
echo "  ECR      : $ECR_REGISTRY"
echo ""
echo "  NEXT STEPS:"
echo "  1. Update CloudFront origin to: $ALB_DNS"
echo "  2. Test:  curl http://$ALB_DNS/api/auth/health"
echo "========================================================"
