#!/bin/bash
# Deploy the built-in web application in a VPC subnet
# Usage: ./deploy-web-app.sh <vpc-name> <subnet-name> [port]

set -e

VPC_NAME=${1:-demo-vpc}
SUBNET_NAME=${2:-public}
PORT=${3:-8000}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_APP_SCRIPT="$PROJECT_ROOT/examples/simple-web-app.py"

if [ ! -f "$WEB_APP_SCRIPT" ]; then
    echo "Error: Web app script not found at $WEB_APP_SCRIPT"
    echo "Falling back to simple HTTP server..."
    ./deploy-app.sh "$VPC_NAME" "$SUBNET_NAME" "python3 -m http.server $PORT" "$PORT"
    exit $?
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

# Copy web app script to a fixed location accessible from namespace
# Use a fixed name so we can reliably find it
SCRIPT_NAME="vpc-web-app-${VPC_NAME}-${SUBNET_NAME}.py"
TMP_WEB_APP="/tmp/$SCRIPT_NAME"
cp "$WEB_APP_SCRIPT" "$TMP_WEB_APP"
chmod +x "$TMP_WEB_APP"

# Make sure the file is accessible (copy with sudo to ensure permissions)
sudo cp "$TMP_WEB_APP" "/tmp/$SCRIPT_NAME" 2>/dev/null || true
sudo chmod 755 "/tmp/$SCRIPT_NAME" 2>/dev/null || true

if [ "$QUIET" != "1" ]; then
    echo "Deploying web application in VPC: $VPC_NAME, Subnet: $SUBNET_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Host IP: $HOST_IP"
    echo "Port: $PORT"
    echo ""
    echo "Starting web application in background..."
fi

# Deploy the application in background
LOG_FILE="/tmp/vpc-app-${VPC_NAME}-${SUBNET_NAME}.log"
PID_FILE="/tmp/vpc-app-${VPC_NAME}-${SUBNET_NAME}.pid"

# Remove old log and PID files
sudo rm -f "$LOG_FILE" "$PID_FILE" 2>/dev/null || true

# Start the Python application in the namespace
# Create a startup script that will run in the namespace and properly daemonize
# Get backend IP and port if private subnet exists (for frontend to connect to backend)
BACKEND_IP=""
BACKEND_PORT="9000"

# First, try to get backend info from URL file (if backend was deployed)
BACKEND_URL_FILE="/tmp/vpc-backend-url-${VPC_NAME}-private.txt"
if [ -f "$BACKEND_URL_FILE" ]; then
    BACKEND_URL=$(cat "$BACKEND_URL_FILE" 2>/dev/null | head -1 | tr -d "[:space:]")
    if [ -n "$BACKEND_URL" ]; then
        # Extract IP and port from URL (format: http://IP:PORT)
        BACKEND_IP=$(echo "$BACKEND_URL" | sed 's|http://||' | cut -d: -f1)
        BACKEND_PORT=$(echo "$BACKEND_URL" | sed 's|http://||' | cut -d: -f2)
        # If port extraction failed, default to 9000
        if [ -z "$BACKEND_PORT" ] || [ "$BACKEND_PORT" = "$BACKEND_IP" ]; then
            BACKEND_PORT="9000"
        fi
    fi
fi

# If backend IP not found from URL file, try to get it from state file
if [ -z "$BACKEND_IP" ] && [ -f "$STATE_FILE" ]; then
    BACKEND_IP=$(python3 -c "
import json
try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
        vpc = data['vpcs']['$VPC_NAME']
        # Try to find private subnet
        for subnet_name, subnet in vpc.get('subnets', {}).items():
            if 'private' in subnet_name.lower() or subnet.get('type') == 'private':
                print(subnet['host_ip'])
                break
except Exception as e:
    print('')
" 2>/dev/null)
fi

# Default values if still not set
BACKEND_IP=${BACKEND_IP:-"10.0.2.2"}
BACKEND_PORT=${BACKEND_PORT:-"9000"}

STARTUP_SCRIPT="/tmp/vpc-start-${VPC_NAME}-${SUBNET_NAME}.sh"
cat > "$STARTUP_SCRIPT" << 'EOF'
#!/bin/bash
cd /tmp

# Export environment variables
export VPC_NAME='VPC_NAME_PLACEHOLDER'
export SUBNET_NAME='SUBNET_NAME_PLACEHOLDER'
export HOST_IP='HOST_IP_PLACEHOLDER'
export NAMESPACE='NAMESPACE_PLACEHOLDER'
export PORT='PORT_PLACEHOLDER'
export BACKEND_IP='BACKEND_IP_PLACEHOLDER'
export BACKEND_PORT='BACKEND_PORT_PLACEHOLDER'

# Verify environment variables are set (for debugging)
# echo "VPC_NAME=$VPC_NAME" >> 'LOG_FILE_PLACEHOLDER'
# echo "BACKEND_IP=$BACKEND_IP" >> 'LOG_FILE_PLACEHOLDER'
# echo "BACKEND_PORT=$BACKEND_PORT" >> 'LOG_FILE_PLACEHOLDER'

# Start Python with environment variables explicitly passed
# Use env to ensure environment is clean and variables are set
env VPC_NAME="$VPC_NAME" \
    SUBNET_NAME="$SUBNET_NAME" \
    HOST_IP="$HOST_IP" \
    NAMESPACE="$NAMESPACE" \
    PORT="$PORT" \
    BACKEND_IP="$BACKEND_IP" \
    BACKEND_PORT="$BACKEND_PORT" \
    python3 'SCRIPT_NAME_PLACEHOLDER' > 'LOG_FILE_PLACEHOLDER' 2>&1 &

PYTHON_PID=$!
echo $PYTHON_PID > 'PID_FILE_PLACEHOLDER'
# Exit immediately - don't wait for Python process
exit 0
EOF

# Ensure BACKEND_IP and BACKEND_PORT have proper values before substitution
BACKEND_IP_VALUE="${BACKEND_IP:-10.0.2.2}"
BACKEND_PORT_VALUE="${BACKEND_PORT:-9000}"

# Verify values before substitution (for debugging)
if [ "$QUIET" != "1" ]; then
    echo "Backend configuration: IP=$BACKEND_IP_VALUE, PORT=$BACKEND_PORT_VALUE"
fi

# Replace placeholders - ensure values are properly set
sed -i "s|VPC_NAME_PLACEHOLDER|$VPC_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|SUBNET_NAME_PLACEHOLDER|$SUBNET_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|HOST_IP_PLACEHOLDER|$HOST_IP|g" "$STARTUP_SCRIPT"
sed -i "s|NAMESPACE_PLACEHOLDER|$NAMESPACE|g" "$STARTUP_SCRIPT"
sed -i "s|PORT_PLACEHOLDER|$PORT|g" "$STARTUP_SCRIPT"
sed -i "s|BACKEND_IP_PLACEHOLDER|$BACKEND_IP_VALUE|g" "$STARTUP_SCRIPT"
sed -i "s|BACKEND_PORT_PLACEHOLDER|$BACKEND_PORT_VALUE|g" "$STARTUP_SCRIPT"
sed -i "s|SCRIPT_NAME_PLACEHOLDER|/tmp/$SCRIPT_NAME|g" "$STARTUP_SCRIPT"
sed -i "s|LOG_FILE_PLACEHOLDER|$LOG_FILE|g" "$STARTUP_SCRIPT"
sed -i "s|PID_FILE_PLACEHOLDER|$PID_FILE|g" "$STARTUP_SCRIPT"
chmod +x "$STARTUP_SCRIPT"
sudo cp "$STARTUP_SCRIPT" "/tmp/$(basename $STARTUP_SCRIPT)" 2>/dev/null || true

# Start the application in the namespace using double-fork pattern for proper daemonization
# This ensures the process is completely orphaned and detached from terminal
DAEMON_SCRIPT="/tmp/vpc-daemon-${VPC_NAME}-${SUBNET_NAME}.sh"
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
    echo "http://$HOST_IP:$PORT" > /tmp/vpc-app-url-${VPC_NAME}-${SUBNET_NAME}.txt 2>/dev/null || true
    echo "$APP_PID" > /tmp/vpc-app-pid-${VPC_NAME}-${SUBNET_NAME}.txt 2>/dev/null || true
    exit 0
else
    # Check log file for errors - this is critical for debugging
    if [ -f "$LOG_FILE" ]; then
        LOG_CONTENT=$(sudo cat "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE" 2>/dev/null || echo "")
        if [ -n "$LOG_CONTENT" ]; then
            echo "ERROR: Application failed to start. Log output:" >&2
            echo "$LOG_CONTENT" | tail -30 >&2
        else
            echo "ERROR: Application failed to start. Log file exists but is empty." >&2
            echo "The process may have crashed immediately or failed to start." >&2
        fi
    else
        echo "ERROR: Application failed to start. Log file not created at $LOG_FILE" >&2
        echo "The startup script may have failed to execute." >&2
    fi
    
    # Clean up on failure
    rm -f "$TMP_WEB_APP" "$STARTUP_SCRIPT" 2>/dev/null || true
    exit 1
fi

# Clean up temp file (optional - can keep it for debugging)
# rm -f "$TMP_WEB_APP"