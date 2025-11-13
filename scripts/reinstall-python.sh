#!/bin/bash
#
# Quick reinstall of camera-recorder package after code changes
#

cd /home/bjoernl/git/n100-videorecorder
pip3 install -e . --break-system-packages --upgrade --force-reinstall --no-deps

echo
echo "Package reinstalled. Testing..."
echo

# Test version
camera-recorder --version

echo
echo "✓ Installation complete!"
