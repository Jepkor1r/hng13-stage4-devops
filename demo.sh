#!/bin/bash
# Helper script to show demo summary with clean formatting

VPC_NAME=${1:-demo-vpc}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Get host IP
HOST_IP=$(cat /tmp/vpc-app-url-${VPC_NAME}-public.txt 2>/dev/null | cut -d'/' -f3 | cut -d':' -f1 2>/dev/null || \
          sudo ./vpcctl show ${VPC_NAME} 2>/dev/null | grep "Host IP:" | head -1 | awk '{print $3}' 2>/dev/null || \
          echo "10.0.1.2")

echo "🌐 Application URL: http://${HOST_IP}:8000"
echo ""
echo "📋 Test with: curl http://${HOST_IP}:8000"
echo "🌍 Or open in browser: http://${HOST_IP}:8000"
echo ""
echo "📝 View VPC: sudo ./vpcctl show ${VPC_NAME}"
echo "🧹 Clean up: make clean"