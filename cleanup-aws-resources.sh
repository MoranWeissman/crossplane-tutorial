#!/bin/bash
set -e

# AWS Cleanup Script for Crossplane-created resources
# Profile: moran-private
# Region: us-east-1 (default region from compositions)

PROFILE="moran-private"
REGION="us-east-1"

echo "=========================================="
echo "AWS Resources Cleanup Script"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Function to run AWS CLI with profile
aws_cmd() {
    aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo "Step 1: Listing and deleting EKS clusters..."
echo "----------------------------------------"
EKS_CLUSTERS=$(aws_cmd eks list-clusters --query 'clusters[]' --output text)
if [ -n "$EKS_CLUSTERS" ]; then
    for CLUSTER in $EKS_CLUSTERS; do
        echo "Found EKS cluster: $CLUSTER"
        
        # Delete node groups first
        NODE_GROUPS=$(aws_cmd eks list-nodegroups --cluster-name "$CLUSTER" --query 'nodegroups[]' --output text)
        if [ -n "$NODE_GROUPS" ]; then
            for NG in $NODE_GROUPS; do
                echo "  Deleting node group: $NG"
                aws_cmd eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" || true
            done
            
            echo "  Waiting for node groups to be deleted..."
            for NG in $NODE_GROUPS; do
                aws_cmd eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$NG" 2>/dev/null || true
            done
        fi
        
        # Delete the cluster
        echo "  Deleting EKS cluster: $CLUSTER"
        aws_cmd eks delete-cluster --name "$CLUSTER" || true
    done
    
    # Wait for clusters to be deleted
    for CLUSTER in $EKS_CLUSTERS; do
        echo "  Waiting for cluster $CLUSTER to be deleted..."
        aws_cmd eks wait cluster-deleted --name "$CLUSTER" 2>/dev/null || true
    done
else
    echo "No EKS clusters found."
fi
echo ""

echo "Step 2: Listing and deleting RDS instances..."
echo "----------------------------------------"
RDS_INSTANCES=$(aws_cmd rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text)
if [ -n "$RDS_INSTANCES" ]; then
    for DB in $RDS_INSTANCES; do
        echo "Found RDS instance: $DB"
        echo "  Deleting RDS instance: $DB (skip-final-snapshot)"
        aws_cmd rds delete-db-instance \
            --db-instance-identifier "$DB" \
            --skip-final-snapshot \
            --delete-automated-backups || true
    done
    
    # Wait for RDS instances to be deleted
    for DB in $RDS_INSTANCES; do
        echo "  Waiting for RDS instance $DB to be deleted..."
        aws_cmd rds wait db-instance-deleted --db-instance-identifier "$DB" 2>/dev/null || true
    done
else
    echo "No RDS instances found."
fi
echo ""

echo "Step 3: Deleting RDS Subnet Groups..."
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

echo "Step 4: Listing and terminating EC2 instances..."
echo "----------------------------------------"
INSTANCES=$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCES" ]; then
    for INSTANCE in $INSTANCES; do
        echo "Found EC2 instance: $INSTANCE"
        aws_cmd ec2 terminate-instances --instance-ids "$INSTANCE" || true
    done
    
    # Wait for instances to terminate
    echo "Waiting for EC2 instances to terminate..."
    aws_cmd ec2 wait instance-terminated --instance-ids $INSTANCES 2>/dev/null || true
else
    echo "No EC2 instances found."
fi
echo ""

echo "Step 5: Cleaning up VPCs and networking..."
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
            # Wait for NAT gateways to be deleted
            sleep 10
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

echo "Step 6: Cleaning up Elastic IPs..."
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

echo "Step 7: Cleaning up Load Balancers..."
echo "----------------------------------------"
# Classic Load Balancers
CLBs=$(aws_cmd elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text)
if [ -n "$CLBs" ]; then
    for CLB in $CLBs; do
        echo "Deleting Classic Load Balancer: $CLB"
        aws_cmd elb delete-load-balancer --load-balancer-name "$CLB" || true
    done
fi

# Application/Network Load Balancers
ALBs=$(aws_cmd elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text)
if [ -n "$ALBs" ]; then
    for ALB in $ALBs; do
        echo "Deleting Load Balancer: $ALB"
        aws_cmd elbv2 delete-load-balancer --load-balancer-arn "$ALB" || true
    done
fi

if [ -z "$CLBs" ] && [ -z "$ALBs" ]; then
    echo "No Load Balancers found."
fi
echo ""

echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Note: Some resources may take a few minutes to fully delete."
echo "You can verify by running:"
echo "  aws --profile $PROFILE --region $REGION ec2 describe-vpcs --filters 'Name=isDefault,Values=false'"
echo "  aws --profile $PROFILE --region $REGION rds describe-db-instances"
echo "  aws --profile $PROFILE --region $REGION eks list-clusters"

