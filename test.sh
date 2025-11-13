#!/bin/bash
# Comprehensive test script for VPC project
# Tests all acceptance criteria

set -e

echo "=========================================="
echo "VPC Project - Comprehensive Test Suite"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

test_info() {
    echo -e "${YELLOW}ℹ️  INFO:${NC} $1"
}

# Cleanup function
cleanup() {
    echo ""
    test_info "Cleaning up test resources..."
    sudo ./vpcctl delete --name testvpc1 2>/dev/null || true
    sudo ./vpcctl delete --name testvpc2 2>/dev/null || true
    sudo ./cleanup.sh 2>/dev/null || true
}

trap cleanup EXIT

echo "Test 1: Create VPC"
echo "-------------------"
if sudo ./vpcctl create --name testvpc1 --cidr 10.0.0.0/16; then
    if ip link show br-testvpc1 >/dev/null 2>&1; then
        test_pass "VPC created and bridge exists"
    else
        test_fail "Bridge not found"
    fi
else
    test_fail "VPC creation failed"
fi
echo ""

echo "Test 2: Add Public Subnet"
echo "-------------------------"
if sudo ./vpcctl add-subnet --vpc testvpc1 --name public --cidr 10.0.1.0/24 --type public; then
    if ip netns list | grep -q ns-testvpc1-public; then
        test_pass "Public subnet created"
    else
        test_fail "Public subnet namespace not found"
    fi
else
    test_fail "Public subnet creation failed"
fi
echo ""

echo "Test 3: Add Private Subnet"
echo "--------------------------"
if sudo ./vpcctl add-subnet --vpc testvpc1 --name private --cidr 10.0.2.0/24 --type private; then
    if ip netns list | grep -q ns-testvpc1-private; then
        test_pass "Private subnet created"
    else
        test_fail "Private subnet namespace not found"
    fi
else
    test_fail "Private subnet creation failed"
fi
echo ""

echo "Test 4: Inter-Subnet Communication"
echo "-----------------------------------"
if sudo ip netns exec ns-testvpc1-public ping -c 2 -W 1 10.0.2.2 >/dev/null 2>&1; then
    test_pass "Public subnet can reach private subnet"
else
    test_fail "Public subnet cannot reach private subnet"
fi

if sudo ip netns exec ns-testvpc1-private ping -c 2 -W 1 10.0.1.2 >/dev/null 2>&1; then
    test_pass "Private subnet can reach public subnet"
else
    test_fail "Private subnet cannot reach public subnet"
fi
echo ""

echo "Test 5: NAT Gateway (Public Subnet)"
echo "------------------------------------"
if sudo ip netns exec ns-testvpc1-public ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    test_pass "Public subnet can access internet (NAT works)"
else
    test_fail "Public subnet cannot access internet"
fi
echo ""

echo "Test 6: Private Subnet Internet Access (Should Fail)"
echo "-----------------------------------------------------"
if sudo ip netns exec ns-testvpc1-private ping -c 2 -W 1 8.8.8.8 >/dev/null 2>&1; then
    test_fail "Private subnet can access internet (should be blocked)"
else
    test_pass "Private subnet correctly blocked from internet"
fi
echo ""

echo "Test 7: Create Second VPC"
echo "-------------------------"
if sudo ./vpcctl create --name testvpc2 --cidr 172.16.0.0/16; then
    if ip link show br-testvpc2 >/dev/null 2>&1; then
        test_pass "Second VPC created"
    else
        test_fail "Second VPC bridge not found"
    fi
else
    test_fail "Second VPC creation failed"
fi
echo ""

echo "Test 8: Add Subnet to Second VPC"
echo "---------------------------------"
if sudo ./vpcctl add-subnet --vpc testvpc2 --name public --cidr 172.16.1.0/24 --type public; then
    test_pass "Subnet added to second VPC"
else
    test_fail "Failed to add subnet to second VPC"
fi
echo ""

echo "Test 9: VPC Isolation (Should Fail)"
echo "------------------------------------"
if sudo ip netns exec ns-testvpc1-public ping -c 2 -W 1 172.16.1.2 >/dev/null 2>&1; then
    test_fail "VPCs can communicate (should be isolated)"
else
    test_pass "VPCs are correctly isolated"
fi
echo ""

echo "Test 10: VPC Peering"
echo "--------------------"
if sudo ./vpcctl peer --vpc1 testvpc1 --vpc2 testvpc2; then
    test_pass "VPC peering created"
    
    # Test connectivity after peering
    sleep 1
    if sudo ip netns exec ns-testvpc1-public ping -c 2 -W 1 172.16.1.2 >/dev/null 2>&1; then
        test_pass "VPCs can communicate after peering"
    else
        test_fail "VPCs cannot communicate after peering"
    fi
else
    test_fail "VPC peering creation failed"
fi
echo ""

echo "Test 11: Deploy Application"
echo "---------------------------"
# Deploy simple HTTP server
sudo ./vpcctl deploy --vpc testvpc1 --subnet public --command "python3 -m http.server 8000 > /dev/null 2>&1" --background
sleep 2

if curl -s -o /dev/null -w "%{http_code}" http://10.0.1.2:8000 | grep -q "200\|403"; then
    test_pass "Application deployed and accessible"
else
    test_fail "Application not accessible"
fi
echo ""

echo "Test 12: Firewall Rules"
echo "-----------------------"
# Create firewall policy
cat > /tmp/test_policy.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

if sudo ./vpcctl apply-firewall --vpc testvpc1 --subnet public --policy /tmp/test_policy.json; then
    test_pass "Firewall rules applied"
    
    # Check if rules exist
    if sudo ip netns exec ns-testvpc1-public iptables -L -n | grep -q "tcp.*80.*ACCEPT"; then
        test_pass "Firewall rule for port 80 exists"
    else
        test_fail "Firewall rule for port 80 not found"
    fi
else
    test_fail "Firewall rule application failed"
fi
echo ""

echo "Test 13: List VPCs"
echo "------------------"
if sudo ./vpcctl list | grep -q testvpc1; then
    test_pass "List command works"
else
    test_fail "List command failed"
fi
echo ""

echo "Test 14: Show VPC Details"
echo "-------------------------"
if sudo ./vpcctl show testvpc1 | grep -q "testvpc1"; then
    test_pass "Show command works"
else
    test_fail "Show command failed"
fi
echo ""

echo "Test 15: Cleanup"
echo "----------------"
if sudo ./vpcctl delete --name testvpc1; then
    if ! ip link show br-testvpc1 >/dev/null 2>&1; then
        test_pass "VPC deletion works"
    else
        test_fail "VPC bridge still exists after deletion"
    fi
else
    test_fail "VPC deletion failed"
fi
echo ""

# Final summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Tests Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Tests Failed:${NC} $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi