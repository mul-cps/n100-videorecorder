#!/bin/bash
#
# N100 Video Recorder Deployment Script
# Automated setup for Intel N100 mini PC with dual 4K USB camera recording
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_USER=${SUDO_USER:-$(whoami)}
BASE_DIR="/storage"
RECORDINGS_DIR="${BASE_DIR}/recordings"
CONFIG_DIR="/etc/camera-recorder"
LOG_DIR="/var/log/camera-recorder"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_system() {
    log "Checking system compatibility..."
    
    # Check if Intel N100 or compatible
    CPU_MODEL=$(lscpu | grep "Model name" | head -1)
    if [[ ! "$CPU_MODEL" =~ "Intel" ]]; then
        warn "This script is optimized for Intel processors. Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check Ubuntu version
    if ! command -v lsb_release &> /dev/null || [[ $(lsb_release -rs | cut -d. -f1) -lt 22 ]]; then
        error "Ubuntu 22.04 or newer is required"
        exit 1
    fi
    
    # Check available storage
    AVAILABLE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    if [[ $AVAILABLE_GB -lt 100 ]]; then
        warn "Less than 100GB available. Ensure adequate storage is mounted at ${BASE_DIR}"
    fi
    
    log "System check passed"
}

setup_wifi() {
    log "Setting up WiFi configuration..."
    
    # Create netplan configuration for WiFi
    cat > /etc/netplan/50-wifi.yaml << 'EOF'
network:
  version: 2
  wifis:
    wlp0s20f3:  # Common WiFi interface for Intel N100
      dhcp4: true
      dhcp6: true
      access-points:
        "SSID_NAME":
          password: "WIFI_PASSWORD"
        "BACKUP_SSID":
          password: "BACKUP_PASSWORD"
EOF
    
    chmod 600 /etc/netplan/50-wifi.yaml
    
    warn "Please edit /etc/netplan/50-wifi.yaml with your WiFi credentials"
    warn "Then run: sudo netplan apply"
    
    log "WiFi configuration template created"
}

install_dependencies() {
    log "Installing system dependencies..."
    
    # Update package lists
    apt update
    
    # Install essential packages
    apt install -y \
        curl \
        wget \
        git \
        htop \
        iotop \
        tree \
        jq \
        usbutils \
        v4l-utils \
        vainfo \
        intel-gpu-tools \
        intel-media-va-driver-non-free
    
    log "System packages installed"
}

setup_intel_drivers() {
    log "Setting up Intel QSV drivers..."
    
    # Install Intel media drivers
    apt install -y \
        intel-media-va-driver-non-free \
        intel-gpu-tools \
        vainfo \
        libmfx1 \
        libmfx-tools
    
    # Add user to video and render groups
    usermod -a -G video,render "$INSTALL_USER"
    
    # Set iHD as default VA driver for better N100 performance
    echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
    
    log "Intel drivers configured"
}

install_jellyfin_ffmpeg() {
    log "Installing Jellyfin FFmpeg with QSV support..."
    
    # Detect Ubuntu version
    UBUNTU_CODENAME=$(lsb_release -cs)
    UBUNTU_VERSION=$(lsb_release -rs)
    
    # Jellyfin only supports LTS releases, so we need to handle non-LTS versions
    # Map non-LTS versions to their base LTS version
    case "$UBUNTU_CODENAME" in
        oracular|plucky)
            # Ubuntu 24.10+ -> use 24.04 LTS (noble) repository
            JELLYFIN_CODENAME="noble"
            warn "Ubuntu $UBUNTU_VERSION detected (non-LTS). Using Ubuntu 24.04 LTS (noble) Jellyfin repository."
            ;;
        mantic)
            # Ubuntu 23.10 -> use 22.04 LTS (jammy) repository
            JELLYFIN_CODENAME="jammy"
            warn "Ubuntu $UBUNTU_VERSION detected (non-LTS). Using Ubuntu 22.04 LTS (jammy) Jellyfin repository."
            ;;
        lunar|kinetic)
            # Ubuntu 23.04, 22.10 -> use 22.04 LTS (jammy) repository
            JELLYFIN_CODENAME="jammy"
            warn "Ubuntu $UBUNTU_VERSION detected (non-LTS). Using Ubuntu 22.04 LTS (jammy) Jellyfin repository."
            ;;
        *)
            # For LTS or unknown versions, use the current codename
            JELLYFIN_CODENAME="$UBUNTU_CODENAME"
            log "Using Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME) Jellyfin repository."
            ;;
    esac
    
    # Install dependencies
    apt install -y curl gnupg apt-transport-https
    
    # Add Jellyfin GPG key
    curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/jellyfin.gpg
    
    # Add Jellyfin repository with the appropriate codename
    echo "deb [arch=$( dpkg --print-architecture )] https://repo.jellyfin.org/ubuntu ${JELLYFIN_CODENAME} main" | tee /etc/apt/sources.list.d/jellyfin.list
    
    # Update package lists
    apt update
    
    # Install jellyfin-ffmpeg (try versioned packages first, fallback to legacy name)
    if apt-cache show jellyfin-ffmpeg7 &>/dev/null; then
        log "Installing jellyfin-ffmpeg7..."
        apt install -y jellyfin-ffmpeg7
        FFMPEG_PATH="/usr/lib/jellyfin-ffmpeg/ffmpeg7"
    elif apt-cache show jellyfin-ffmpeg6 &>/dev/null; then
        log "Installing jellyfin-ffmpeg6..."
        apt install -y jellyfin-ffmpeg6
        FFMPEG_PATH="/usr/lib/jellyfin-ffmpeg/ffmpeg6"
    else
        log "Installing jellyfin-ffmpeg (legacy)..."
        apt install -y jellyfin-ffmpeg
        FFMPEG_PATH="/usr/lib/jellyfin-ffmpeg/ffmpeg"
    fi
    
    # Create symlink for easier access
    ln -sf "$FFMPEG_PATH" /usr/local/bin/ffmpeg-qsv
    
    log "FFmpeg with QSV support installed at $FFMPEG_PATH"
}

setup_directories() {
    log "Setting up directory structure..."
    
    # Create base directories
    mkdir -p "$RECORDINGS_DIR"/{cam1,cam2,logs}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # Set ownership
    chown -R "$INSTALL_USER:$INSTALL_USER" "$BASE_DIR"
    chown -R "$INSTALL_USER:$INSTALL_USER" "$CONFIG_DIR"
    
    # Set permissions
    chmod -R 755 "$RECORDINGS_DIR"
    chmod -R 750 "$CONFIG_DIR"
    
    log "Directory structure created"
}

install_scripts() {
    log "Installing recording scripts..."
    
    # Copy scripts to system location
    cp scripts/*.sh /usr/local/bin/
    chmod +x /usr/local/bin/camera-*.sh
    chmod +x /usr/local/bin/dual-camera-*.sh
    
    # Copy configuration files
    cp config/* "$CONFIG_DIR/" 2>/dev/null || true
    
    log "Scripts installed to /usr/local/bin/"
}

setup_systemd() {
    log "Setting up systemd service..."
    
    # Copy service file
    cp systemd/dual-camera-record.service /etc/systemd/system/
    
    # Update service file with correct user
    sed -i "s/youruser/$INSTALL_USER/g" /etc/systemd/system/dual-camera-record.service
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable service
    systemctl enable dual-camera-record.service
    
    log "Systemd service configured and enabled"
}

setup_udev_rules() {
    log "Setting up USB camera udev rules..."
    
    # Copy udev rules for persistent camera mapping
    cp udev/99-camera-mapping.rules /etc/udev/rules.d/
    
    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger
    
    log "USB camera mapping rules installed"
}

setup_logrotate() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/camera-recorder << 'EOF'
/var/log/camera-recorder/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su root root
}
EOF
    
    log "Log rotation configured"
}

setup_cleanup_cron() {
    log "Setting up automatic cleanup..."
    
    # Create cleanup script
    cat > /usr/local/bin/cleanup-recordings.sh << 'EOF'
#!/bin/bash
# Cleanup old recordings to prevent disk full

BASE_DIR="/storage/recordings"
DAYS_TO_KEEP=30
DISK_USAGE_THRESHOLD=95

# Remove files older than specified days
find "$BASE_DIR" -name "*.mp4" -mtime +$DAYS_TO_KEEP -delete

# Check disk usage and remove oldest files if over threshold
DISK_USAGE=$(df "$BASE_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt "$DISK_USAGE_THRESHOLD" ]; then
    # Remove oldest files until under threshold
    find "$BASE_DIR" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -n | head -n 10 | cut -d' ' -f2- | xargs -r rm -f
fi
EOF
    
    chmod +x /usr/local/bin/cleanup-recordings.sh
    
    # Add to crontab (run daily at 2 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/cleanup-recordings.sh") | crontab -
    
    log "Automatic cleanup configured"
}

verify_installation() {
    log "Verifying installation..."
    
    # Check QSV support
    if ! /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q qsv; then
        warn "QSV encoders not detected - hardware acceleration may not work"
    else
        log "QSV encoders detected successfully"
    fi
    
    # Check VA-API
    if ! vainfo --display drm --device /dev/dri/renderD128 &>/dev/null; then
        warn "VA-API not working properly"
    else
        log "VA-API is functional"
    fi
    
    # Check directories
    if [[ ! -d "$RECORDINGS_DIR" ]]; then
        error "Recordings directory not created"
        exit 1
    fi
    
    log "Installation verification completed"
}

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  N100 Video Recorder Deployment${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    check_root
    check_system
    
    log "Starting deployment..."
    
    setup_wifi
    install_dependencies
    setup_intel_drivers
    install_jellyfin_ffmpeg
    setup_directories
    install_scripts
    setup_systemd
    setup_udev_rules
    setup_logrotate
    setup_cleanup_cron
    verify_installation
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Configure WiFi: sudo nano /etc/netplan/50-wifi.yaml"
    echo "2. Apply network config: sudo netplan apply"
    echo "3. Setup cameras: sudo /usr/local/bin/camera-setup.sh"
    echo "4. Test recording: sudo /usr/local/bin/camera-test.sh"
    echo "5. Start service: sudo systemctl start dual-camera-record"
    echo
    echo -e "${BLUE}Logs:${NC} journalctl -u dual-camera-record -f"
    echo -e "${BLUE}Status:${NC} systemctl status dual-camera-record"
    echo
}

main "$@"
