#!/bin/bash
#
# System-wide installation script for Camera Recorder
# This uses system package manager (apt) instead of pip
#

set -e

echo "========================================"
echo "Camera Recorder - System Installation"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run with sudo"
    echo "Usage: sudo ./install-system.sh"
    exit 1
fi

# Detect package manager
if command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
else
    echo "ERROR: No supported package manager found (apt/dnf/yum)"
    exit 1
fi

echo "📦 Installing system packages..."
echo ""

if [ "$PKG_MANAGER" = "apt" ]; then
    # Debian/Ubuntu
    apt update
    apt install -y \
        python3 \
        python3-yaml \
        python3-psutil \
        python3-flask \
        python3-werkzeug \
        python3-pip
    
    echo ""
    echo "✅ System packages installed"
    echo ""
    echo "📦 Installing camera-recorder package..."
    
    # Get the script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    
    # Install with --break-system-packages for Debian 12+
    pip3 install --break-system-packages -e . || {
        echo "⚠️  Standard install failed, trying alternative..."
        # Try copying files manually
        cp -r src/camera_recorder /usr/local/lib/python3.*/dist-packages/ 2>/dev/null || {
            echo "ERROR: Installation failed"
            echo "Please use the venv-based install.sh instead"
            exit 1
        }
    }
    
elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
    # RHEL/Fedora/CentOS
    $PKG_MANAGER install -y \
        python3 \
        python3-pyyaml \
        python3-psutil \
        python3-flask \
        python3-werkzeug \
        python3-pip
    
    # Get the script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    
    pip3 install -e .
fi

echo ""
echo "✅ System-wide installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure cameras in /etc/camera-recorder/config.yaml"
echo "   sudo mkdir -p /etc/camera-recorder"
echo "   sudo cp config.yaml.example /etc/camera-recorder/config.yaml"
echo "   sudo nano /etc/camera-recorder/config.yaml"
echo ""
echo "2. Detect cameras:"
echo "   camera-recorder --detect"
echo ""
echo "3. Validate configuration:"
echo "   camera-recorder --validate"
echo ""
echo "4. Install systemd service:"
echo "   sudo cp systemd/camera-recorder-python.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable camera-recorder-python"
echo "   sudo systemctl start camera-recorder-python"
echo ""
echo "5. Access web interface:"
echo "   http://$(hostname -I | awk '{print $1}'):8080"
echo ""
