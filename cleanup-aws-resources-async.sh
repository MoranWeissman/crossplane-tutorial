#!/bin/bash
set -e

# AWS Cleanup Script for Crossplane-created resources (Async - No Waiting)
# Profile: moran-private
# Region: us-east-1

PROFILE="moran-private"
REGION="us-east-1"

echo "=========================================="
echo "AWS Resources Cleanup Script (Async Mode)"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Function to run AWS CLI with profile
aws_cmd() {
    aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo "Step 1: Deleting EKS node groups (async)..."
echo "----------------------------------------"
aws_cmd eks delete-nodegroup --cluster-name cluster-01 --nodegroup-name cluster-01 2>/dev/null || echo "Node group already deleting or deleted"
echo "✓ Node group deletion initiated"
echo ""

echo "Step 2: Deleting EKS cluster (async)..."
echo "----------------------------------------"
aws_cmd eks delete-cluster --name cluster-01 2>/dev/null || echo "Cluster already deleting or deleted"
echo "✓ EKS cluster deletion initiated (will delete after node groups are gone)"
echo ""

echo "Step 3: Deleting RDS instance (async)..."
echo "----------------------------------------"
aws_cmd rds delete-db-instance \
    --db-instance-identifier terraform-20251011094907032300000007 \
    --skip-final-snapshot \
    --delete-automated-backups 2>/dev/null || echo "RDS already deleting or deleted"
echo "✓ RDS instance deletion initiated"
echo ""

echo "=========================================="
echo "All deletions initiated!"
echo "=========================================="
echo ""
echo "Resources are being deleted in the background."
echo "This will take 20-40 minutes to complete."
echo ""
echo "To check progress, run:"
echo "  ./list-aws-resources.sh"
echo ""
echo "Once EKS and RDS are deleted, run this to clean up networking:"
echo "  ./cleanup-aws-networking.sh"

