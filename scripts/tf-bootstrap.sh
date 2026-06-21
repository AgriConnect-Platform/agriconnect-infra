#!/bin/bash
# Run this ONCE before terraform init.
# Creates the S3 bucket for remote state storage.
set -e

BUCKET="agriconnect-terraform-state"
REGION="ap-south-1"

echo "Creating S3 state bucket: $BUCKET in $REGION"

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ""
echo "Done. S3 bucket ready: s3://$BUCKET"
echo "Now run: terraform init -migrate-state"
