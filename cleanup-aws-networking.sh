#!/bin/bash
set -e

# AWS Networking Cleanup Script
# Profile: moran-private
# Region: us-east-1
# Run this AFTER EKS and RDS are fully deleted

PROFILE="moran-private"
REGION="us-east-1"

echo "=========================================="
echo "AWS Networking Cleanup Script"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Function to run AWS CLI with profile
aws_cmd() {
    aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo "Step 1: Checking if EKS and RDS are deleted..."
echo "----------------------------------------"
EKS_COUNT=$(aws_cmd eks list-clusters --query 'clusters | length(@)' --output text)
RDS_COUNT=$(aws_cmd rds describe-db-instances --query 'DBInstances | length(@)' --output text)

if [ "$EKS_COUNT" -ne 0 ] || [ "$RDS_COUNT" -ne 0 ]; then
    echo "⚠️  Warning: EKS clusters or RDS instances still exist!"
    echo "   EKS clusters: $EKS_COUNT"
    echo "   RDS instances: $RDS_COUNT"
    echo ""
    echo "Please wait for them to finish deleting before cleaning networking."
    echo "You can check status with: ./list-aws-resources.sh"
    exit 1
fi
echo "✓ EKS and RDS are deleted"
echo ""

echo "Step 2: Deleting RDS Subnet Groups..."
echo "----------------------------------------"
SUBNET_GROUPS=$(aws_cmd rds describe-db-subnet-groups --query 'DBSubnetGroups[].DBSubnetGroupName' --output text)
if [ -n "$SUBNET_GROUPS" ]; then
    for SG in $SUBNET_GROUPS; do
        if [[ "$SG" != "default" ]]; then
            echo "Deleting RDS subnet group: $SG"
            aws_cmd rds delete-db-subnet-group --db-subnet-group-name "$SG" || true
        fi
    done
else
    echo "No RDS subnet groups found."
fi
echo ""

echo "Step 3: Cleaning up VPCs and networking..."
echo "----------------------------------------"
# Get all non-default VPCs
VPCS=$(aws_cmd ec2 describe-vpcs --filters "Name=isDefault,Values=false" --query 'Vpcs[].VpcId' --output text)

if [ -n "$VPCS" ]; then
    for VPC in $VPCS; do
        echo "Processing VPC: $VPC"
        
        # Delete NAT Gateways
        NAT_GWS=$(aws_cmd ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=$VPC" "Name=state,Values=available" \
            --query 'NatGateways[].NatGatewayId' --output text)
        if [ -n "$NAT_GWS" ]; then
            for NAT in $NAT_GWS; do
                echo "  Deleting NAT Gateway: $NAT"
                aws_cmd ec2 delete-nat-gateway --nat-gateway-id "$NAT" || true
            done
            echo "  Waiting 30s for NAT gateways to start deleting..."
            sleep 30
        fi
        
        # Delete Load Balancers in this VPC
        LBs=$(aws_cmd elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC'].LoadBalancerArn" --output text 2>/dev/null || true)
        if [ -n "$LBs" ]; then
            for LB in $LBs; do
                echo "  Deleting Load Balancer: $LB"
                aws_cmd elbv2 delete-load-balancer --load-balancer-arn "$LB" || true
            done
            echo "  Waiting 30s for load balancers to start deleting..."
            sleep 30
        fi
        
        # Detach and delete Internet Gateways
        IGWs=$(aws_cmd ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$VPC" \
            --query 'InternetGateways[].InternetGatewayId' --output text)
        if [ -n "$IGWs" ]; then
            for IGW in $IGWs; do
                echo "  Detaching Internet Gateway: $IGW"
                aws_cmd ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC" || true
                echo "  Deleting Internet Gateway: $IGW"
                aws_cmd ec2 delete-internet-gateway --internet-gateway-id "$IGW" || true
            done
        fi
        
        # Delete subnets
        SUBNETS=$(aws_cmd ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC" \
            --query 'Subnets[].SubnetId' --output text)
        if [ -n "$SUBNETS" ]; then
            for SUBNET in $SUBNETS; do
                echo "  Deleting Subnet: $SUBNET"
                aws_cmd ec2 delete-subnet --subnet-id "$SUBNET" || true
            done
        fi
        
        # Delete route table associations and route tables
        ROUTE_TABLES=$(aws_cmd ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC" \
            --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text)
        if [ -n "$ROUTE_TABLES" ]; then
            for RT in $ROUTE_TABLES; do
                echo "  Deleting Route Table: $RT"
                aws_cmd ec2 delete-route-table --route-table-id "$RT" || true
            done
        fi
        
        # Delete security groups (except default)
        SECURITY_GROUPS=$(aws_cmd ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        if [ -n "$SECURITY_GROUPS" ]; then
            for SG in $SECURITY_GROUPS; do
                echo "  Deleting Security Group: $SG"
                aws_cmd ec2 delete-security-group --group-id "$SG" || true
            done
        fi
        
        # Finally, delete the VPC
        echo "  Deleting VPC: $VPC"
        aws_cmd ec2 delete-vpc --vpc-id "$VPC" || true
        echo ""
    done
else
    echo "No non-default VPCs found."
fi
echo ""

echo "Step 4: Cleaning up Elastic IPs..."
echo "----------------------------------------"
EIPs=$(aws_cmd ec2 describe-addresses --query 'Addresses[].AllocationId' --output text)
if [ -n "$EIPs" ]; then
    for EIP in $EIPs; do
        echo "Releasing Elastic IP: $EIP"
        aws_cmd ec2 release-address --allocation-id "$EIP" || true
    done
else
    echo "No Elastic IPs found."
fi
echo ""

echo "=========================================="
echo "Networking Cleanup Complete!"
echo "=========================================="
echo ""
echo "Run './list-aws-resources.sh' to verify all resources are gone."

