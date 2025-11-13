#!/bin/bash
#
# Setup Automated HEVC Transcoding
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "============================================"
echo "  Setup Automated HEVC Transcoding"
echo "============================================"
echo

# Check if running as user (not root)
if [[ $EUID -eq 0 ]]; then
    warn "Don't run this script as root. It will use sudo when needed."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

log "Installing transcode script..."
sudo cp "$REPO_DIR/scripts/transcode-old-recordings.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/transcode-old-recordings.sh

log "Installing systemd service and timer..."
sudo cp "$REPO_DIR/systemd/transcode-recordings.service" /etc/systemd/system/
sudo cp "$REPO_DIR/systemd/transcode-recordings.timer" /etc/systemd/system/

log "Reloading systemd..."
sudo systemctl daemon-reload

log "Enabling timer (will run daily at 2 AM)..."
sudo systemctl enable transcode-recordings.timer
sudo systemctl start transcode-recordings.timer

echo
log "Installation complete!"
echo
echo "Configuration:"
echo "  - Files older than 2 days will be transcoded to HEVC"
echo "  - Runs automatically every day at 2 AM"
echo "  - Original H.264 files are replaced with HEVC versions"
echo "  - Saves approximately 50% disk space"
echo
echo "Commands:"
echo "  Check timer status:    systemctl status transcode-recordings.timer"
echo "  Check service status:  systemctl status transcode-recordings.service"
echo "  View logs:             journalctl -u transcode-recordings.service"
echo "  Run manually now:      sudo systemctl start transcode-recordings.service"
echo "  Disable auto-transcode: sudo systemctl disable transcode-recordings.timer"
echo
echo "Customization:"
echo "  Edit /etc/systemd/system/transcode-recordings.service to change:"
echo "    - TRANSCODE_AGE_DAYS (currently 2 days)"
echo "    - ENCODING_QUALITY (currently 23)"
echo "    - ENCODING_PRESET (currently medium)"
echo
