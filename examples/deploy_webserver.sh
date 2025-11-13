#!/bin/bash
# Example: Deploy a web server in a VPC subnet
# This demonstrates application deployment

set -e

echo "=== Web Server Deployment Example ==="
echo ""

VPC_NAME="webapp-vpc"
SUBNET_NAME="public"

# Clean up any existing VPC
echo "Step 1: Cleaning up any existing '${VPC_NAME}'..."
sudo ./vpcctl delete --name ${VPC_NAME} 2>/dev/null || true
sleep 1

# Create VPC
echo "Step 2: Creating VPC '${VPC_NAME}'..."
sudo ./vpcctl create --name ${VPC_NAME} --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc ${VPC_NAME} --name ${SUBNET_NAME} --cidr 10.0.1.0/24 --type public

# Get the host IP from VPC state
HOST_IP=$(python3 -c "
import json
import sys
try:
    with open('.vpcctl/vpcs.json', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['${VPC_NAME}']
        subnet = vpc['subnets']['${SUBNET_NAME}']
        print(subnet['host_ip'])
except:
    print('10.0.1.2')  # Default fallback
")

echo ""
echo "Step 3: Deploying web server in ${SUBNET_NAME} subnet..."
echo "Server will be accessible at http://${HOST_IP}:8000"

# Deploy web server in background
sudo ./vpcctl deploy --vpc ${VPC_NAME} --subnet ${SUBNET_NAME} \
    --command "python3 -m http.server 8000" --background

# Wait for server to start
echo "Waiting for server to start..."
sleep 3

# Test HTTP access
echo ""
echo "Step 4: Testing HTTP access..."
if curl -s -o /dev/null -w "%{http_code}" http://${HOST_IP}:8000 | grep -q "200\|403\|301"; then
    echo "✅ Web server is accessible!"
    echo "Try: curl http://${HOST_IP}:8000"
else
    echo "⚠️  Web server may still be starting, or check firewall rules"
fi

echo ""
echo "✅ Web server deployment example complete!"
echo "Server is running in background. To stop it, find the process and kill it."
echo "To clean up VPC: sudo ./vpcctl delete --name ${VPC_NAME}"