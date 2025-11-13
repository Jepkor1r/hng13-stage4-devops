#!/bin/bash
# Example: Deploy a web application and show the URL
# This demonstrates deploying an app and accessing it

set -e

echo "=== Deploy Web Application and Show URL ==="
echo ""

VPC_NAME="demo-vpc"
SUBNET_NAME="public"

# Clean up any existing VPC
echo "Step 1: Cleaning up any existing '${VPC_NAME}'..."
sudo ./vpcctl delete --name ${VPC_NAME} 2>/dev/null || true
sleep 1

# Create VPC
echo "Step 2: Creating VPC '${VPC_NAME}'..."
sudo ./vpcctl create --name ${VPC_NAME} --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc ${VPC_NAME} --name ${SUBNET_NAME} --cidr 10.0.1.0/24 --type public

# Deploy web application (using built-in web app)
echo ""
echo "Step 3: Deploying web application..."
URL=$(sudo ./vpcctl deploy --vpc ${VPC_NAME} --subnet ${SUBNET_NAME} --command web --background 2>&1 | grep "Application URL:" | awk '{print $3}' || echo "")

if [ -z "$URL" ]; then
    # Fallback: get URL from state file
    URL=$(python3 -c "
import json
try:
    with open('.vpcctl/vpcs.json', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['${VPC_NAME}']
        subnet = vpc['subnets']['${SUBNET_NAME}']
        host_ip = subnet['host_ip']
        print(f'http://{host_ip}:8000')
except:
    print('http://10.0.1.2:8000')
")
fi

echo ""
echo "Step 4: Waiting for server to start..."
sleep 3

# Test the URL
echo ""
echo "Step 5: Testing application..."
if curl -s -o /dev/null -w "%{http_code}" "$URL" | grep -q "200\|403\|301"; then
    echo "✅ Application is running!"
    echo ""
    echo "=========================================="
    echo "🌐 Application URL: $URL"
    echo "=========================================="
    echo ""
    echo "📋 Access it with:"
    echo "   curl $URL"
    echo ""
    echo "🌍 Or open in your browser:"
    echo "   $URL"
    echo ""
    echo "📝 To view the HTML:"
    echo "   curl $URL | head -20"
    echo ""
else
    echo "⚠️  Application may still be starting..."
    echo "🌐 URL: $URL"
    echo "   Try: curl $URL"
fi

echo ""
echo "✅ Deployment complete!"
echo "To clean up: sudo ./vpcctl delete --name ${VPC_NAME}"