#!/bin/bash


set +e  # Don’t exit on errors. Keep cleaning up everything

# --- Simple logging setup ---
GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[1;33m"; RESET="\033[0m"
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }

log "Starting VPC cleanup..."

# --- Step 0: Delete all existing VPCs via vpcctl ---
log "Step 0: Removing all defined VPCs..."
if command -v ./vpcctl >/dev/null 2>&1 || command -v vpcctl >/dev/null 2>&1; then
    VPCCTL="./vpcctl"
    [[ ! -x "$VPCCTL" ]] && VPCCTL="vpcctl"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    STATE_FILE="$SCRIPT_DIR/.vpcctl/vpcs.json"

    # Try fallback paths if not found
    [[ ! -f "$STATE_FILE" ]] && STATE_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/.vpcctl/vpcs.json"
    [[ ! -f "$STATE_FILE" ]] && STATE_FILE="$HOME/.vpcctl/vpcs.json"

    if [[ -f "$STATE_FILE" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            VPC_NAMES=$(python3 -c "import json; f=open('$STATE_FILE'); print('\n'.join(json.load(f).get('vpcs', {}).keys()))" 2>/dev/null)
        else
            VPC_NAMES=$(grep -o '"name":[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/' | sort -u)
        fi

        if [[ -n "$VPC_NAMES" ]]; then
            for vpc in $VPC_NAMES; do
                log "Deleting VPC → $vpc"
                sudo $VPCCTL delete --name "$vpc" 2>/dev/null || true
            done
        else
            warn "No VPCs listed in state file."
        fi
    else
        warn "No VPC state file found. Skipping VPC deletion."
    fi
else
    warn "vpcctl not detected in PATH — skipping automated deletion."
fi

# --- Step 1: Remove all namespaces ---
log "Step 1: Removing network namespaces..."
for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
    log "Deleting namespace: $ns"
    sudo ip netns delete "$ns" 2>/dev/null || true
done

# --- Step 2: Detach interfaces from bridges ---
log "Step 2: Detaching veth interfaces from bridges..."
for br in $(ip link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(br-|vpc)'); do
    log "Processing bridge: $br"
    for iface in $(brctl show "$br" 2>/dev/null | tail -n +2 | awk '{print $NF}' | grep -v '^$'); do
        log "→ Detaching $iface"
        sudo ip link set "$iface" nomaster 2>/dev/null || true
        sudo ip link set "$iface" down 2>/dev/null || true
    done
done

# --- Step 3: Bring down veth pairs ---
log "Step 3: Bringing down veth interfaces..."
for veth in $(ip link show type veth 2>/dev/null | awk -F': ' '{print $2}' | awk -F'@' '{print $1}'); do
    log "Downing: $veth"
    sudo ip link set "$veth" down 2>/dev/null || true
    sudo ip link set "$veth" nomaster 2>/dev/null || true
done

# --- Step 4: Delete all bridges ---
log "Step 4: Removing bridges..."
for br in $(ip link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(br-|vpc)'); do
    log "Deleting bridge: $br"
    sudo ip link set "$br" down 2>/dev/null || true
    sudo ip link delete "$br" 2>/dev/null || true
done

# --- Step 5: Delete remaining veths ---
log "Step 5: Deleting leftover veth pairs..."
for veth in $(ip link show type veth 2>/dev/null | awk -F': ' '{print $2}' | awk -F'@' '{print $1}' | sort -u); do
    log "Removing: $veth"
    sudo ip link delete "$veth" 2>/dev/null || true
done

# --- Step 6: Clean routes ---
log "Step 6: Removing old routes..."
for cidr in 10.0.0.0/16 172.16.0.0/16 192.168.0.0/16; do
    sudo ip route del "$cidr" 2>/dev/null || true
done

ip route show | grep -E 'veth-peer|br-|via.*192\.168' | while read line; do
    dest=$(echo "$line" | awk '{print $1}')
    [[ "$dest" != "default" ]] && sudo ip route del "$dest" 2>/dev/null || true
done

# --- Step 7: Remove NAT rules ---
log "Step 7: Cleaning NAT rules..."
for rule in $(sudo iptables -t nat -L POSTROUTING -n --line-numbers | grep -E '10\.0\.|172\.16\.' | awk '{print $1}' | sort -rn); do
    log "Deleting NAT rule: $rule"
    sudo iptables -t nat -D POSTROUTING "$rule" 2>/dev/null || true
done

# --- Step 8: Forwarding cleanup ---
log "Step 8: Cleaning forwarding rules..."
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT 2>/dev/null || true

# --- Step 9: Reset sysctl ---
log "Step 9: Resetting system network settings..."
sudo sysctl -w net.ipv4.conf.all.proxy_arp=0 2>/dev/null || true

# --- Step 10: Cleanup config files ---
log "Step 10: Removing VPC control files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.vpcctl/vpcs.json"
LOG_PATH="$SCRIPT_DIR/.vpcctl/vpcctl.log"

[[ ! -f "$STATE_FILE" ]] && STATE_FILE="$HOME/.vpcctl/vpcs.json"
[[ ! -f "$LOG_PATH" ]] && LOG_PATH="$HOME/.vpcctl/vpcctl.log"

[[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE" && log "Deleted $STATE_FILE"
[[ -f "$LOG_PATH" ]] && mv "$LOG_PATH" "${LOG_PATH}.bak.$(date +%F_%H%M)" && log "Backed up $LOG_PATH"

# --- Step 11: Verify results ---
echo ""
log "Verification Summary:"
echo "  → Namespaces: $(ip netns list 2>/dev/null | wc -l)"
echo "  → Bridges: $(ip link show type bridge 2>/dev/null | grep -E '^(br-|vpc)' | wc -l)"
echo "  → veth pairs: $(ip link show type veth 2>/dev/null | grep -c veth || echo 0)"
echo "  → State file present: $( [[ -f "$STATE_FILE" ]] && echo 'Yes' || echo 'No' )"
echo ""

log "✅ Cleanup finished. Any leftovers above may need manual inspection."