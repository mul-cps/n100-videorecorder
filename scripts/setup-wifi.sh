#!/bin/bash
#
# Network Setup Script - Configure WiFi for N100 mini PC
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

detect_wifi_interface() {
    log "Detecting WiFi interface..."
    
    # Common interface names for Intel N100 systems
    local interfaces=("wlp0s20f3" "wlan0" "wlp1s0" "wlp2s0")
    local found_interface=""
    
    for iface in "${interfaces[@]}"; do
        if ip link show "$iface" &>/dev/null; then
            found_interface="$iface"
            log "Found WiFi interface: $iface"
            break
        fi
    done
    
    if [[ -z "$found_interface" ]]; then
        # Try to find any wireless interface
        found_interface=$(iw dev | grep Interface | awk '{print $2}' | head -1)
        if [[ -n "$found_interface" ]]; then
            log "Found WiFi interface: $found_interface"
        else
            error "No WiFi interface found!"
            exit 1
        fi
    fi
    
    echo "$found_interface"
}

setup_wifi_config() {
    local wifi_interface="$1"
    
    log "Setting up WiFi configuration for interface: $wifi_interface"
    
    # Backup existing netplan config
    if [[ -f /etc/netplan/50-wifi.yaml ]]; then
        cp /etc/netplan/50-wifi.yaml /etc/netplan/50-wifi.yaml.backup
        log "Backed up existing WiFi config"
    fi
    
    # Create WiFi configuration
    cat > /etc/netplan/50-wifi.yaml << EOF
network:
  version: 2
  renderer: networkd
  wifis:
    $wifi_interface:
      dhcp4: true
      dhcp6: true
      optional: true
      access-points:
        "REPLACE_WITH_YOUR_SSID":
          password: "REPLACE_WITH_YOUR_PASSWORD"
      # Disable power management for stability
      powersave: false
EOF
    
    chmod 600 /etc/netplan/50-wifi.yaml
    
    warn "WiFi configuration created at /etc/netplan/50-wifi.yaml"
    warn "IMPORTANT: Edit this file with your actual WiFi credentials:"
    warn "  sudo nano /etc/netplan/50-wifi.yaml"
    warn "Then apply the configuration:"
    warn "  sudo netplan apply"
}

configure_wifi_power_management() {
    log "Configuring WiFi power management for stability..."
    
    # Disable WiFi power management for better stability
    cat > /etc/systemd/system/disable-wifi-powersave.service << 'EOF'
[Unit]
Description=Disable WiFi Power Management
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iw dev wlp0s20f3 set power_save off
ExecStart=/sbin/iw dev wlan0 set power_save off
RemainAfterExit=yes
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable disable-wifi-powersave.service 2>/dev/null || true
    log "WiFi power management optimization configured"
}

install_wifi_tools() {
    log "Installing WiFi management tools..."
    
    apt update
    apt install -y \
        wireless-tools \
        wpasupplicant \
        iw \
        rfkill \
        network-manager \
        net-tools
    
    log "WiFi tools installed"
}

check_wifi_hardware() {
    log "Checking WiFi hardware..."
    
    # Check for WiFi devices
    if lspci | grep -i "wireless\|wifi\|802.11" &>/dev/null; then
        log "WiFi hardware detected:"
        lspci | grep -i "wireless\|wifi\|802.11"
    else
        warn "No WiFi hardware detected via PCI"
    fi
    
    # Check for USB WiFi adapters
    if lsusb | grep -i "wireless\|wifi\|802.11" &>/dev/null; then
        log "USB WiFi hardware detected:"
        lsusb | grep -i "wireless\|wifi\|802.11"
    fi
    
    # Check rfkill status
    if command -v rfkill &>/dev/null; then
        log "WiFi radio status:"
        rfkill list wifi || warn "No WiFi radios found"
    fi
}

setup_connection_monitoring() {
    log "Setting up connection monitoring..."
    
    # Create connection monitoring script
    cat > /usr/local/bin/monitor-wifi.sh << 'EOF'
#!/bin/bash
# WiFi Connection Monitor

INTERFACE=$(iw dev | grep Interface | awk '{print $2}' | head -1)
LOG_FILE="/var/log/wifi-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

check_connection() {
    # Check if interface is up
    if ! ip link show "$INTERFACE" | grep -q "state UP"; then
        log_message "WARNING: Interface $INTERFACE is down"
        return 1
    fi
    
    # Check if we have an IP address
    if ! ip addr show "$INTERFACE" | grep -q "inet "; then
        log_message "WARNING: No IP address on $INTERFACE"
        return 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        log_message "WARNING: No internet connectivity"
        return 1
    fi
    
    return 0
}

# Main monitoring loop
while true; do
    if check_connection; then
        # Log success every hour
        if (( $(date +%M) == 0 )); then
            log_message "INFO: WiFi connection healthy"
        fi
    else
        log_message "ERROR: WiFi connection problem detected"
        # Try to restart networking
        systemctl restart systemd-networkd
        sleep 30
    fi
    
    sleep 60
done
EOF
    
    chmod +x /usr/local/bin/monitor-wifi.sh
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/wifi-monitor.service << 'EOF'
[Unit]
Description=WiFi Connection Monitor
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/monitor-wifi.sh
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable wifi-monitor.service
    log "WiFi monitoring service configured"
}

main() {
    echo -e "${GREEN}============================${NC}"
    echo -e "${GREEN}   WiFi Setup for N100${NC}"
    echo -e "${GREEN}============================${NC}"
    echo
    
    check_wifi_hardware
    echo
    
    install_wifi_tools
    echo
    
    wifi_interface=$(detect_wifi_interface)
    setup_wifi_config "$wifi_interface"
    echo
    
    configure_wifi_power_management
    echo
    
    setup_connection_monitoring
    echo
    
    echo -e "${GREEN}WiFi setup complete!${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit WiFi credentials: sudo nano /etc/netplan/50-wifi.yaml"
    echo "2. Apply configuration: sudo netplan apply"  
    echo "3. Check status: ip addr show $wifi_interface"
    echo "4. Test connectivity: ping google.com"
    echo
    echo -e "${YELLOW}Monitoring:${NC}"
    echo "WiFi logs: tail -f /var/log/wifi-monitor.log"
    echo "Service status: systemctl status wifi-monitor"
}

main "$@"
