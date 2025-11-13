#!/bin/bash
# Example: Apply firewall rules to a subnet
# This demonstrates security group functionality

set -e

echo "=== Firewall Rules Example ==="
echo ""

VPC_NAME="secure-vpc"
SUBNET_NAME="public"

# Clean up any existing VPC
echo "Step 1: Cleaning up any existing '${VPC_NAME}'..."
sudo ./vpcctl delete --name ${VPC_NAME} 2>/dev/null || true
sleep 1

# Create VPC
echo "Step 2: Creating VPC '${VPC_NAME}'..."
sudo ./vpcctl create --name ${VPC_NAME} --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc ${VPC_NAME} --name ${SUBNET_NAME} --cidr 10.0.1.0/24 --type public

# Create firewall policy
echo ""
echo "Step 3: Creating firewall policy..."
cat > /tmp/firewall-policy.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ],
  "egress": [
    {"port": 0, "protocol": "all", "action": "allow"}
  ]
}
EOF

# Apply firewall policy
echo "Step 4: Applying firewall policy..."
sudo ./vpcctl apply-firewall --vpc ${VPC_NAME} --subnet ${SUBNET_NAME} --policy /tmp/firewall-policy.json

# Deploy web server
echo ""
echo "Step 5: Deploying web server..."
HOST_IP=$(python3 -c "
import json
try:
    with open('.vpcctl/vpcs.json', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['${VPC_NAME}']
        subnet = vpc['subnets']['${SUBNET_NAME}']
        print(subnet['host_ip'])
except:
    print('10.0.1.2')
")

sudo ./vpcctl deploy --vpc ${VPC_NAME} --subnet ${SUBNET_NAME} \
    --command "python3 -m http.server 80" --background

sleep 2

# Test firewall rules
echo ""
echo "Step 6: Testing firewall rules..."
echo "Testing HTTP (port 80) - should work:"
if curl -s -o /dev/null -w "%{http_code}" http://${HOST_IP}:80 | grep -q "200\|403\|301"; then
    echo "✅ HTTP (port 80) is allowed"
else
    echo "⚠️  HTTP test"
fi

echo "Testing SSH (port 22) - should be blocked:"
if timeout 2 bash -c "echo > /dev/tcp/${HOST_IP}/22" 2>/dev/null; then
    echo "⚠️  SSH (port 22) is not blocked"
else
    echo "✅ SSH (port 22) is blocked"
fi

echo ""
echo "✅ Firewall rules example complete!"
echo "To clean up: sudo ./vpcctl delete --name ${VPC_NAME}"
rm -f /tmp/firewall-policy.json