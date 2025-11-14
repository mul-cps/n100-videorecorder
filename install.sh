#!/bin/bash
#
# Install/Update script for Camera Recorder with Web Interface
#

set -e

echo "================================"
echo "Camera Recorder - Installation"
echo "================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "ERROR: Please do not run this script as root"
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "📦 Installing Python dependencies..."
pip3 install --user -e . || {
    echo "ERROR: Failed to install Python package"
    exit 1
}

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure cameras in /etc/camera-recorder/config.yaml"
echo "   (or copy from config.yaml.example)"
echo ""
echo "2. Detect cameras:"
echo "   camera-recorder --detect"
echo ""
echo "3. Validate configuration:"
echo "   camera-recorder --validate"
echo ""
echo "4. Test run (foreground):"
echo "   camera-recorder"
echo ""
echo "5. Install systemd service:"
echo "   sudo cp systemd/camera-recorder-python.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable camera-recorder-python"
echo "   sudo systemctl start camera-recorder-python"
echo ""
echo "6. Access web interface:"
echo "   http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "📚 Documentation:"
echo "   - Web Interface: WEB_INTERFACE.md"
echo "   - Python Guide: PYTHON_README.md"
echo "   - Transcoding: TRANSCODING_FEATURE_SUMMARY.md"
echo ""
