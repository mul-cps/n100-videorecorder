#!/bin/bash
#
# Install and configure systemd service for Camera Recorder
#

set -e

echo "========================================="
echo "Camera Recorder - Service Installation"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run with sudo"
    echo "Usage: sudo ./install-service.sh [username]"
    exit 1
fi

# Detect the actual user (not root)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
elif [ -n "$1" ]; then
    ACTUAL_USER="$1"
    ACTUAL_HOME=$(getent passwd "$1" | cut -d: -f6)
else
    echo "ERROR: Could not determine user"
    echo "Usage: sudo ./install-service.sh [username]"
    echo "Example: sudo ./install-service.sh bjoern"
    exit 1
fi

# Verify user exists
if ! id "$ACTUAL_USER" &>/dev/null; then
    echo "ERROR: User '$ACTUAL_USER' does not exist"
    exit 1
fi

echo "📝 Configuring service for user: $ACTUAL_USER"
echo "   Home directory: $ACTUAL_HOME"
echo ""

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create temporary service file with correct user
TEMP_SERVICE=$(mktemp)
cat > "$TEMP_SERVICE" << EOF
[Unit]
Description=Camera Recorder Service (Python)
After=network.target
Wants=network.target

[Service]
Type=simple
User=$ACTUAL_USER
Group=video
WorkingDirectory=$SCRIPT_DIR
Environment="LIBVA_DRIVER_NAME=iHD"
Environment="PYTHONUNBUFFERED=1"

# Wait for cameras to be ready
ExecStartPre=/bin/sleep 5

# Main recording command
ExecStart=/usr/local/bin/camera-recorder --config /etc/camera-recorder/config.yaml

# Graceful shutdown
KillSignal=SIGINT
TimeoutStopSec=20
KillMode=mixed

# Restart configuration
Restart=on-failure
RestartSec=10
StartLimitInterval=300
StartLimitBurst=5

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=camera-recorder

# Security and permissions
NoNewPrivileges=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
ProtectKernelModules=false
RestrictRealtime=true

# Device access
DeviceAllow=/dev/dri/renderD128 rw
DeviceAllow=/dev/dri/card0 rw
DeviceAllow=/dev/video0 rw
DeviceAllow=/dev/video1 rw
DeviceAllow=/dev/video2 rw
DeviceAllow=/dev/video3 rw
DeviceAllow=/dev/video4 rw
DeviceAllow=/dev/video5 rw
DeviceAllow=/dev/video6 rw
DeviceAllow=/dev/video7 rw
SupplementaryGroups=video render

# Resource limits
LimitNOFILE=4096
OOMScoreAdjust=-100

[Install]
WantedBy=multi-user.target
EOF

echo "📦 Installing systemd service..."

# Copy service file
cp "$TEMP_SERVICE" /etc/systemd/system/camera-recorder-python.service
rm "$TEMP_SERVICE"

# Reload systemd
systemctl daemon-reload

echo ""
echo "✅ Service installed successfully!"
echo ""
echo "Next steps:"
echo ""
echo "1. Enable service to start on boot:"
echo "   sudo systemctl enable camera-recorder-python"
echo ""
echo "2. Start the service:"
echo "   sudo systemctl start camera-recorder-python"
echo ""
echo "3. Check status:"
echo "   sudo systemctl status camera-recorder-python"
echo ""
echo "4. View logs:"
echo "   sudo journalctl -u camera-recorder-python -f"
echo ""
echo "5. Access web interface:"
echo "   http://localhost:8080"
echo ""
