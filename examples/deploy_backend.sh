#!/bin/bash
# Deploy the backend API in a VPC subnet (typically private subnet)
# Usage: ./deploy-backend-api.sh <vpc-name> <subnet-name> [port]

set -e

VPC_NAME=${1:-demo-vpc}
SUBNET_NAME=${2:-private}
PORT=${3:-9000}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_SCRIPT="$PROJECT_ROOT/examples/backend-api.py"

if [ ! -f "$BACKEND_SCRIPT" ]; then
    echo "Error: Backend API script not found at $BACKEND_SCRIPT"
    exit 1
fi

# Get namespace and IP from vpcctl state
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

# Copy backend script to a fixed location accessible from namespace
SCRIPT_NAME="vpc-backend-api-${VPC_NAME}-${SUBNET_NAME}.py"
TMP_BACKEND="/tmp/$SCRIPT_NAME"
cp "$BACKEND_SCRIPT" "$TMP_BACKEND"
chmod +x "$TMP_BACKEND"

# Make sure the file is accessible (copy with sudo to ensure permissions)
sudo cp "$TMP_BACKEND" "/tmp/$SCRIPT_NAME" 2>/dev/null || true
sudo chmod 755 "/tmp/$SCRIPT_NAME" 2>/dev/null || true

if [ "$QUIET" != "1" ]; then
    echo "Deploying backend API in VPC: $VPC_NAME, Subnet: $SUBNET_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Host IP: $HOST_IP"
    echo "Port: $PORT"
    echo ""
    echo "Starting backend API in background..."
fi

# Deploy the application in background
LOG_FILE="/tmp/vpc-backend-${VPC_NAME}-${SUBNET_NAME}.log"
PID_FILE="/tmp/vpc-backend-${VPC_NAME}-${SUBNET_NAME}.pid"

# Remove old log and PID files
sudo rm -f "$LOG_FILE" "$PID_FILE" 2>/dev/null || true

# Start the Python application in the namespace
STARTUP_SCRIPT="/tmp/vpc-start-backend-${VPC_NAME}-${SUBNET_NAME}.sh"
cat > "$STARTUP_SCRIPT" << 'EOF'
#!/bin/bash
cd /tmp
export VPC_NAME='VPC_NAME_PLACEHOLDER'
export SUBNET_NAME='SUBNET_NAME_PLACEHOLDER'
export HOST_IP='HOST_IP_PLACEHOLDER'
export NAMESPACE='NAMESPACE_PLACEHOLDER'
export PORT='PORT_PLACEHOLDER'

# Start Python in background, redirecting all I/O to log file
python3 'SCRIPT_NAME_PLACEHOLDER' > 'LOG_FILE_PLACEHOLDER' 2>&1 &
PYTHON_PID=$!
echo $PYTHON_PID > 'PID_FILE_PLACEHOLDER'
# Exit immediately - don't wait for Python process
exit 0
EOF

# Replace placeholders
sed -i "s|VPC_NAME_PLACEHOLDER|$VPC_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|SUBNET_NAME_PLACEHOLDER|$SUBNET_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|HOST_IP_PLACEHOLDER|$HOST_IP|g" "$STARTUP_SCRIPT"
sed -i "s|NAMESPACE_PLACEHOLDER|$NAMESPACE|g" "$STARTUP_SCRIPT"
sed -i "s|PORT_PLACEHOLDER|$PORT|g" "$STARTUP_SCRIPT"
sed -i "s|SCRIPT_NAME_PLACEHOLDER|/tmp/$SCRIPT_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|LOG_FILE_PLACEHOLDER|$LOG_FILE|g" "$STARTUP_SCRIPT"
sed -i "s|PID_FILE_PLACEHOLDER|$PID_FILE|g" "$STARTUP_SCRIPT"
chmod +x "$STARTUP_SCRIPT"
sudo cp "$STARTUP_SCRIPT" "/tmp/$(basename $STARTUP_SCRIPT)" 2>/dev/null || true

# Start the application in the namespace using double-fork pattern for proper daemonization
DAEMON_SCRIPT="/tmp/vpc-daemon-backend-${VPC_NAME}-${SUBNET_NAME}.sh"
cat > "$DAEMON_SCRIPT" << 'DAEMON_EOF'
#!/bin/bash
# Double-fork daemon pattern
(
  # First fork - background this subshell
  (
    # Second fork - start the actual process
    sudo ip netns exec NAMESPACE_PLACEHOLDER bash '/tmp/STARTUP_SCRIPT_PLACEHOLDER' < /dev/null > /dev/null 2>&1 &
    # Parent of second fork exits immediately
    exit 0
  )
  # Parent of first fork exits immediately, orphaning the grandchild
  exit 0
) &
# Disown so shell doesn't track it
disown 2>/dev/null || true
DAEMON_EOF

sed -i "s|NAMESPACE_PLACEHOLDER|$NAMESPACE|g" "$DAEMON_SCRIPT"
sed -i "s|STARTUP_SCRIPT_PLACEHOLDER|$(basename $STARTUP_SCRIPT)|g" "$DAEMON_SCRIPT"
chmod +x "$DAEMON_SCRIPT"

# Run the daemon script
bash "$DAEMON_SCRIPT" 2>/dev/null

# Clean up daemon script
rm -f "$DAEMON_SCRIPT" 2>/dev/null || true

# Wait for startup script to run and PID file to be created
sleep 3

# Get PID from file
APP_PID=$(sudo cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || echo "")

# Wait a bit more for Python to actually start
sleep 2

# Verify the PID is correct - if not, find by process name
if [ -z "$APP_PID" ] || ! sudo ip netns exec $NAMESPACE kill -0 $APP_PID 2>/dev/null; then
    APP_PID=$(sudo ip netns exec $NAMESPACE pgrep -f "python3.*$SCRIPT_NAME" | head -1 || echo "")
fi

# Wait a bit more and verify the process is running
sleep 2

# Verify process is running - check multiple ways
RUNNING=false

# Method 1: Check if we found a PID and it's running
if [ -n "$APP_PID" ] && [ "$APP_PID" -gt 0 ] 2>/dev/null; then
    if sudo ip netns exec $NAMESPACE kill -0 $APP_PID 2>/dev/null; then
        RUNNING=true
    fi
fi

# Method 2: Check if port is listening (most reliable)
if [ "$RUNNING" = "false" ]; then
    # Try to connect to the port
    if timeout 2 bash -c "echo > /dev/tcp/$HOST_IP/$PORT" 2>/dev/null; then
        RUNNING=true
        # Find PID by port
        APP_PID=$(sudo ip netns exec $NAMESPACE ss -tlnp 2>/dev/null | grep ":$PORT " | grep -oP 'pid=\K\d+' | head -1 || echo "")
    fi
fi

# Method 3: Check process list one more time
if [ "$RUNNING" = "false" ]; then
    APP_PID=$(sudo ip netns exec $NAMESPACE pgrep -f "python3.*$SCRIPT_NAME" 2>/dev/null | head -1 || echo "")
    if [ -n "$APP_PID" ]; then
        RUNNING=true
    fi
fi

# Clean up temporary files
rm -f "$STARTUP_SCRIPT" 2>/dev/null || true
sudo rm -f "/tmp/$(basename $STARTUP_SCRIPT)" 2>/dev/null || true

# Report results
if [ "$RUNNING" = "true" ] && [ -n "$APP_PID" ]; then
    # Save URL and PID for reference
    echo "http://$HOST_IP:$PORT" > /tmp/vpc-backend-url-${VPC_NAME}-${SUBNET_NAME}.txt 2>/dev/null || true
    echo "$APP_PID" > /tmp/vpc-backend-pid-${VPC_NAME}-${SUBNET_NAME}.txt 2>/dev/null || true
    if [ "$QUIET" != "1" ]; then
        echo "✅ Backend API deployed successfully!"
        echo ""
        echo "🌐 Backend API URL: http://$HOST_IP:$PORT"
        echo "📝 Process ID: $APP_PID"
        echo "📋 Logs: $LOG_FILE"
        echo "🛑 To stop: sudo kill $APP_PID"
    fi
    exit 0
else
    # Check log file for errors - this is critical for debugging
    if [ -f "$LOG_FILE" ]; then
        LOG_CONTENT=$(sudo cat "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE" 2>/dev/null || echo "")
        if [ -n "$LOG_CONTENT" ]; then
            echo "ERROR: Backend API failed to start. Log output:" >&2
            echo "$LOG_CONTENT" | tail -30 >&2
        else
            echo "ERROR: Backend API failed to start. Log file exists but is empty." >&2
            echo "The process may have crashed immediately or failed to start." >&2
        fi
    else
        echo "ERROR: Backend API failed to start. Log file not created at $LOG_FILE" >&2
        echo "The startup script may have failed to execute." >&2
    fi
    
    # Clean up on failure
    rm -f "$TMP_BACKEND" "$STARTUP_SCRIPT" 2>/dev/null || true
    exit 1
fi