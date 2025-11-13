#!/bin/bash
# Example: Create a basic VPC with public and private subnets
# This demonstrates the basic VPC setup

set -e

echo "=== Basic VPC Example ==="
echo ""

# Clean up any existing VPC with the same name
echo "Step 1: Cleaning up any existing 'example-vpc'..."
sudo ./vpcctl delete --name example-vpc 2>/dev/null || true
sleep 1

# Create VPC
echo "Step 2: Creating VPC 'example-vpc' with CIDR 10.0.0.0/16..."
sudo ./vpcctl create --name example-vpc --cidr 10.0.0.0/16

# Add public subnet
echo "Step 3: Adding public subnet 10.0.1.0/24..."
sudo ./vpcctl add-subnet --vpc example-vpc --name public --cidr 10.0.1.0/24 --type public

# Add private subnet
echo "Step 4: Adding private subnet 10.0.2.0/24..."
sudo ./vpcctl add-subnet --vpc example-vpc --name private --cidr 10.0.2.0/24 --type private

# Show VPC details
echo ""
echo "Step 5: VPC Details:"
sudo ./vpcctl show example-vpc

# Test connectivity
echo ""
echo "Step 6: Testing inter-subnet connectivity..."
echo "Testing: public subnet -> private subnet"
sudo ip netns exec ns-example-vpc-public ping -c 2 10.0.2.2 || echo "⚠️  Ping failed (this is expected if namespaces aren't fully configured)"

echo ""
echo "Step 7: Testing internet access from public subnet..."
sudo ip netns exec ns-example-vpc-public ping -c 2 8.8.8.8 || echo "⚠️  Internet access test (may require NAT configuration)"

echo ""
echo "✅ Basic VPC created successfully!"
echo "To clean up: sudo ./vpcctl delete --name example-vpc"