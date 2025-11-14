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

# Detect if we're in an externally-managed environment
EXTERNALLY_MANAGED=false
if pip3 install --help 2>&1 | grep -q "externally-managed-environment"; then
    EXTERNALLY_MANAGED=true
fi

echo "📦 Installing Python dependencies..."
echo ""

# Try different installation methods
if [ -f "venv/bin/activate" ]; then
    # Virtual environment already exists
    echo "✓ Using existing virtual environment"
    source venv/bin/activate
    pip install -e .
    INSTALL_SUCCESS=true
elif command -v pipx &> /dev/null; then
    # Use pipx if available
    echo "✓ Installing via pipx..."
    pipx install -e . --force || {
        echo "⚠️  pipx install failed, trying alternative methods..."
        INSTALL_SUCCESS=false
    }
    if [ "${INSTALL_SUCCESS}" != "false" ]; then
        INSTALL_SUCCESS=true
    fi
else
    # Create virtual environment
    echo "ℹ️  Detected externally-managed Python environment"
    echo "   Creating virtual environment for isolated installation..."
    echo ""
    
    # Check if python3-venv is available
    if ! python3 -m venv --help &> /dev/null; then
        echo "ERROR: python3-venv module not found"
        echo ""
        echo "Please install it first:"
        echo "  sudo apt install python3-venv python3-full"
        echo ""
        echo "Or install dependencies system-wide (Debian/Ubuntu):"
        echo "  sudo apt install python3-yaml python3-psutil python3-flask python3-werkzeug"
        exit 1
    fi
    
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -e .
    INSTALL_SUCCESS=true
fi

if [ "${INSTALL_SUCCESS}" != "true" ]; then
    echo ""
    echo "⚠️  Standard installation failed. Trying system package installation..."
    echo ""
    echo "To install system-wide (requires sudo):"
    echo "  sudo apt install python3-yaml python3-psutil python3-flask python3-werkzeug"
    echo ""
    echo "Or use pip with --break-system-packages (not recommended):"
    echo "  pip3 install --user --break-system-packages -e ."
    exit 1
fi

echo ""
echo "✅ Installation complete!"
echo ""

# Provide activation instructions if using venv
if [ -f "venv/bin/activate" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 IMPORTANT: Virtual environment created!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "To use the camera recorder:"
    echo ""
    echo "  1. Activate the virtual environment:"
    echo "     source venv/bin/activate"
    echo ""
    echo "  2. Run the recorder:"
    echo "     camera-recorder"
    echo ""
    echo "  Or run directly without activation:"
    echo "     ./venv/bin/camera-recorder"
    echo ""
    echo "For systemd service, update the ExecStart path to:"
    echo "  ExecStart=$SCRIPT_DIR/venv/bin/camera-recorder -c /etc/camera-recorder/config.yaml"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

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
