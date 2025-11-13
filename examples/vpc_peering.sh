#!/bin/bash
# Example: Create two VPCs and connect them with peering
# This demonstrates VPC isolation and peering

set -e

echo "=== VPC Peering Example ==="
echo ""

# Clean up any existing VPCs
echo "Step 1: Cleaning up any existing VPCs..."
sudo ./vpcctl delete --name vpc1 2>/dev/null || true
sudo ./vpcctl delete --name vpc2 2>/dev/null || true
sleep 1

# Create first VPC
echo "Step 2: Creating VPC1 (10.0.0.0/16)..."
sudo ./vpcctl create --name vpc1 --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc vpc1 --name public --cidr 10.0.1.0/24 --type public

# Create second VPC
echo "Step 3: Creating VPC2 (172.16.0.0/16)..."
sudo ./vpcctl create --name vpc2 --cidr 172.16.0.0/16
sudo ./vpcctl add-subnet --vpc vpc2 --name public --cidr 172.16.1.0/24 --type public

# Test isolation (should fail)
echo ""
echo "Step 4: Testing VPC isolation (should fail)..."
if sudo ip netns exec ns-vpc1-public ping -c 1 -W 1 172.16.1.2 >/dev/null 2>&1; then
    echo "⚠️  VPCs can communicate (isolation may not be enforced)"
else
    echo "✅ VPCs are isolated (cannot communicate)"
fi

# Create peering
echo ""
echo "Step 5: Creating VPC peering..."
sudo ./vpcctl peer --vpc1 vpc1 --vpc2 vpc2

# Test connectivity after peering (should work)
echo ""
echo "Step 6: Testing connectivity after peering (should work)..."
sleep 1
if sudo ip netns exec ns-vpc1-public ping -c 2 -W 1 172.16.1.2 >/dev/null 2>&1; then
    echo "✅ VPCs can communicate after peering!"
else
    echo "⚠️  Peering may need a moment to establish, or check routes"
fi

echo ""
echo "✅ VPC peering example complete!"
echo "To clean up: sudo ./vpcctl delete --name vpc1 && sudo ./vpcctl delete --name vpc2"