#!/bin/bash
# Run this ONCE before `terraform apply` to replace ACCOUNT_ID_PLACEHOLDER
# with your real AWS account ID in the import blocks.
#
# Usage: bash scripts/set-account-id.sh
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region 2>/dev/null || echo "ap-south-1")

if [ -z "$ACCOUNT_ID" ]; then
  echo "ERROR: Could not get AWS account ID. Is AWS CLI configured?"
  exit 1
fi

echo "Account ID : $ACCOUNT_ID"
echo "Region     : $REGION"
echo ""

# Replace placeholders in main.tf
sed -i \
  "s|ACCOUNT_ID_PLACEHOLDER|$ACCOUNT_ID|g; s|ap-south-1|$REGION|g" \
  "$(dirname "$0")/../main.tf"

echo "main.tf updated with account ID $ACCOUNT_ID and region $REGION"
echo "You can now run: terraform init && terraform apply"
