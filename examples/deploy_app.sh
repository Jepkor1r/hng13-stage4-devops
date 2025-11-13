#!/bin/bash
# Helper script to deploy applications in VPC subnets
# Usage: ./deploy-app.sh <vpc-name> <subnet-name> <command> [port]

set -e

VPC_NAME=${1:-}
SUBNET_NAME=${2:-}
COMMAND=${3:-"python3 -m http.server 8000"}
PORT=${4:-8000}

if [ -z "$VPC_NAME" ] || [ -z "$SUBNET_NAME" ]; then
    echo "Usage: $0 <vpc-name> <subnet-name> <command> [port]"
    echo "Example: $0 myvpc public 'python3 -m http.server 8000' 8000"
    exit 1
fi

# Get namespace and IP from vpcctl state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$PROJECT_ROOT/.vpcctl/vpcs.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "Error: State file not found. Is the VPC created?"
    exit 1
fi

# Extract namespace and IP using Python
NAMESPACE=$(python3 -c "
import json
try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['$VPC_NAME']
        subnet = vpc['subnets']['$SUBNET_NAME']
        print(subnet['namespace'])
except Exception as e:
    print('')
" 2>/dev/null)

HOST_IP=$(python3 -c "
import json
try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['$VPC_NAME']
        subnet = vpc['subnets']['$SUBNET_NAME']
        print(subnet['host_ip'])
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$NAMESPACE" ] || [ -z "$HOST_IP" ]; then
    echo "Error: Could not find subnet $SUBNET_NAME in VPC $VPC_NAME" >&2
    echo "Run: sudo ./vpcctl show $VPC_NAME" >&2
    exit 1
fi

# Check for quiet mode (when called from Makefile)
QUIET=${QUIET:-0}

if [ "$QUIET" != "1" ]; then
    echo "Deploying application in VPC: $VPC_NAME, Subnet: $SUBNET_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Host IP: $HOST_IP"
    echo "Command: $COMMAND"
    echo ""
    echo "Starting application in background..."
fi

# Deploy the application in background (properly daemonized)
LOG_FILE="/tmp/vpc-app-${VPC_NAME}-${SUBNET_NAME}.log"
PID_FILE="/tmp/vpc-app-${VPC_NAME}-${SUBNET_NAME}.pid"

# Create a wrapper script to properly daemonize the process
WRAPPER_SCRIPT="/tmp/vpc-wrapper-$$.sh"
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
cd /tmp
LOG_FILE="$1"
PID_FILE="$2"
COMMAND="$3"

# Start the process in background with full daemonization
nohup setsid bash -c "$COMMAND" < /dev/null > "$LOG_FILE" 2>&1 &
APP_PID=$!
echo $APP_PID > "$PID_FILE"
exit 0
WRAPPER_EOF
chmod +x "$WRAPPER_SCRIPT"

# Run the wrapper in the namespace with proper arguments
sudo ip netns exec $NAMESPACE bash "$WRAPPER_SCRIPT" "$LOG_FILE" "$PID_FILE" "$COMMAND" 2>/dev/null

# Wait a moment for PID file to be created and process to start
sleep 2

# Get the PID (need sudo to read if created by root in namespace)
APP_PID=$(sudo cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]')
sudo rm -f "$WRAPPER_SCRIPT" "$PID_FILE" 2>/dev/null

# Verify process is running - check if process exists in namespace
if [ -n "$APP_PID" ] && [ "$APP_PID" -gt 0 ] 2>/dev/null; then
    # Check if process is actually running in the namespace
    if sudo ip netns exec $NAMESPACE ps -p $APP_PID > /dev/null 2>&1; then
        RUNNING=true
    else
        RUNNING=false
    fi
else
    RUNNING=false
fi

if [ "$RUNNING" = "true" ]; then
    # Save URL for reference
    echo "http://$HOST_IP:$PORT" > /tmp/vpc-app-url-${VPC_NAME}-${SUBNET_NAME}.txt 2>/dev/null || true
    
    if [ "$QUIET" != "1" ]; then
        echo "✅ Application deployed successfully!"
        echo ""
        echo "=========================================="
        echo "🌐 Application URL: http://$HOST_IP:$PORT"
        echo "=========================================="
        echo ""
        echo "📋 Test with: curl http://$HOST_IP:$PORT"
        echo "🌍 Or open in browser: http://$HOST_IP:$PORT"
        echo ""
        echo "📝 Process ID: $APP_PID"
        echo "   Logs: $LOG_FILE"
        echo "   To stop: sudo kill $APP_PID"
    fi
    exit 0
else
    echo "ERROR: Application failed to start" >&2
    if [ -f "$LOG_FILE" ]; then
        echo "Check logs: $LOG_FILE" >&2
        sudo tail -20 "$LOG_FILE" 2>/dev/null || tail -20 "$LOG_FILE" 2>/dev/null || echo "Could not read log file" >&2
    fi
    exit 1
fi