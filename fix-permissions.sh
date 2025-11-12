#!/bin/bash
#
# Quick Permission Fix Script
# Fixes device permissions and adds user to required groups
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

USER_NAME=${SUDO_USER:-$USER}

echo -e "${GREEN}Fixing camera and GPU permissions...${NC}"

# Add user to video and render groups
echo "Adding $USER_NAME to video and render groups..."
sudo usermod -a -G video,render "$USER_NAME"

# Fix current video device permissions
if compgen -G "/dev/video*" > /dev/null; then
    echo "Fixing /dev/video* permissions..."
    for dev in /dev/video*; do
        if [[ -c "$dev" ]]; then
            sudo chown root:video "$dev"
            sudo chmod 660 "$dev"
        fi
    done
fi

# Install udev rules
if [[ -f "udev/99-camera-mapping.rules" ]]; then
    echo "Installing udev rules..."
    sudo cp udev/99-camera-mapping.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi

echo
echo -e "${GREEN}Permissions fixed!${NC}"
echo
echo -e "${YELLOW}IMPORTANT: You must do ONE of the following:${NC}"
echo "  1) Log out and log back in (recommended)"
echo "  2) Run: newgrp render"
echo "     Then run your tests in that new shell"
echo
echo "To verify your groups after re-login:"
echo "  groups"
echo "  (should include: video render)"
echo
echo "To test camera access:"
echo "  ./scripts/camera-test.sh"
