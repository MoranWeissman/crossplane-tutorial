#!/bin/bash

# AWS Resources Listing Script
# Profile: moran-private
# Region: us-east-1

PROFILE="moran-private"
REGION="us-east-1"

echo "=========================================="
echo "AWS Resources Audit"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Function to run AWS CLI with profile
aws_cmd() {
    aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo "EKS Clusters:"
echo "----------------------------------------"
aws_cmd eks list-clusters --output table || echo "Error listing EKS clusters"
echo ""

echo "RDS Instances:"
echo "----------------------------------------"
aws_cmd rds describe-db-instances \
    --query 'DBInstances[].{Name:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Size:DBInstanceClass}' \
    --output table || echo "No RDS instances found"
echo ""

echo "EC2 Instances:"
echo "----------------------------------------"
aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,stopped,stopping,pending" \
    --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table || echo "No EC2 instances found"
echo ""

echo "VPCs (non-default):"
echo "----------------------------------------"
aws_cmd ec2 describe-vpcs \
    --filters "Name=isDefault,Values=false" \
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table || echo "No non-default VPCs found"
echo ""

echo "Internet Gateways:"
echo "----------------------------------------"
aws_cmd ec2 describe-internet-gateways \
    --query 'InternetGateways[].{ID:InternetGatewayId,VPC:Attachments[0].VpcId,State:Attachments[0].State}' \
    --output table || echo "No Internet Gateways found"
echo ""

echo "NAT Gateways:"
echo "----------------------------------------"
aws_cmd ec2 describe-nat-gateways \
    --filter "Name=state,Values=available,pending,deleting" \
    --query 'NatGateways[].{ID:NatGatewayId,VPC:VpcId,State:State}' \
    --output table || echo "No NAT Gateways found"
echo ""

echo "Subnets (in non-default VPCs):"
echo "----------------------------------------"
aws_cmd ec2 describe-subnets \
    --query 'Subnets[].{ID:SubnetId,VPC:VpcId,CIDR:CidrBlock,AZ:AvailabilityZone}' \
    --output table || echo "No Subnets found"
echo ""

echo "Security Groups (non-default):"
echo "----------------------------------------"
aws_cmd ec2 describe-security-groups \
    --filters "Name=group-name,Values=*" \
    --query 'SecurityGroups[?GroupName!=`default`].{ID:GroupId,Name:GroupName,VPC:VpcId}' \
    --output table || echo "No non-default Security Groups found"
echo ""

echo "Elastic IPs:"
echo "----------------------------------------"
aws_cmd ec2 describe-addresses \
    --query 'Addresses[].{IP:PublicIp,AllocationID:AllocationId,Instance:InstanceId}' \
    --output table || echo "No Elastic IPs found"
echo ""

echo "Load Balancers (ALB/NLB):"
echo "----------------------------------------"
aws_cmd elbv2 describe-load-balancers \
    --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code,VPC:VpcId}' \
    --output table 2>/dev/null || echo "No ALB/NLB found"
echo ""

echo "Classic Load Balancers:"
echo "----------------------------------------"
aws_cmd elb describe-load-balancers \
    --query 'LoadBalancerDescriptions[].{Name:LoadBalancerName,VPC:VPCId}' \
    --output table 2>/dev/null || echo "No Classic Load Balancers found"
echo ""

echo "RDS Subnet Groups:"
echo "----------------------------------------"
aws_cmd rds describe-db-subnet-groups \
    --query 'DBSubnetGroups[].{Name:DBSubnetGroupName,VPC:VpcId}' \
    --output table || echo "No RDS Subnet Groups found"
echo ""

echo "=========================================="
echo "Audit Complete!"
echo "=========================================="

