#!/bin/bash
#
# Automatic Camera Detection Script
# Detects USB cameras and identifies the correct video capture devices
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo "============================================"
echo "  USB Camera Auto-Detection"
echo "============================================"
echo

# Function to check if a device is a capture device (not metadata)
is_capture_device() {
    local device=$1
    
    # Check if device supports video capture formats
    v4l2-ctl --device="$device" --list-formats 2>&1 | grep -q "H264\|MJPG\|YUYV"
    return $?
}

# Function to get camera info
get_camera_info() {
    local device=$1
    
    local card=$(v4l2-ctl --device="$device" --info 2>/dev/null | grep "Card type" | cut -d: -f2 | xargs)
    local bus=$(v4l2-ctl --device="$device" --info 2>/dev/null | grep "Bus info" | cut -d: -f2 | xargs)
    local formats=$(v4l2-ctl --device="$device" --list-formats 2>/dev/null | grep -E "MJPG|H264|YUYV" | head -1 | awk '{print $2}' | tr -d "'")
    
    echo "$card|$bus|$formats"
}

log "Scanning for video devices..."
echo

# Find all video devices
video_devices=()
for device in /dev/video*[0-9]; do
    if [[ -c "$device" ]]; then
        video_devices+=("$device")
    fi
done

if [[ ${#video_devices[@]} -eq 0 ]]; then
    echo "No video devices found!"
    exit 1
fi

echo "Found ${#video_devices[@]} video device(s)"
echo

# Detect capture devices (not metadata)
capture_devices=()

for device in "${video_devices[@]}"; do
    if is_capture_device "$device"; then
        capture_devices+=("$device")
        info=$(get_camera_info "$device")
        
        echo -e "${BLUE}✓ Capture Device: $device${NC}"
        echo "  Card: $(echo $info | cut -d'|' -f1)"
        echo "  Bus: $(echo $info | cut -d'|' -f2)"
        echo "  Formats: $(echo $info | cut -d'|' -f3)"
        
        # Check for persistent symlinks
        for symlink in /dev/video-*; do
            if [[ -L "$symlink" ]] && [[ "$(readlink -f $symlink)" == "$device" ]]; then
                echo -e "  ${GREEN}Persistent Link: $symlink${NC}"
            fi
        done
        echo
    fi
done

if [[ ${#capture_devices[@]} -eq 0 ]]; then
    echo "No capture devices found!"
    exit 1
fi

log "Detected ${#capture_devices[@]} capture device(s)"
echo

# Suggest configuration
if [[ ${#capture_devices[@]} -ge 2 ]]; then
    echo -e "${GREEN}Recommended Configuration:${NC}"
    echo
    echo "CAMERA1_DEVICE=\"${capture_devices[0]}\""
    echo "CAMERA2_DEVICE=\"${capture_devices[1]}\""
    echo
    
    # Check if persistent symlinks exist
    cam1_symlink=""
    cam2_symlink=""
    
    for symlink in /dev/video-usb*-video*; do
        if [[ -L "$symlink" ]]; then
            target=$(readlink -f "$symlink")
            if [[ "$target" == "${capture_devices[0]}" ]]; then
                cam1_symlink="$symlink"
            elif [[ "$target" == "${capture_devices[1]}" ]]; then
                cam2_symlink="$symlink"
            fi
        fi
    done
    
    if [[ -n "$cam1_symlink" ]] && [[ -n "$cam2_symlink" ]]; then
        echo -e "${GREEN}Better (using persistent symlinks):${NC}"
        echo
        echo "CAMERA1_DEVICE=\"$cam1_symlink\""
        echo "CAMERA2_DEVICE=\"$cam2_symlink\""
        echo
        
        # Offer to update configuration
        if [[ -f "/etc/camera-recorder/camera-mapping.conf" ]]; then
            echo -e "${YELLOW}Update /etc/camera-recorder/camera-mapping.conf with these values? (y/n)${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                sudo sed -i "s|^CAMERA1_DEVICE=.*|CAMERA1_DEVICE=\"$cam1_symlink\"|" /etc/camera-recorder/camera-mapping.conf
                sudo sed -i "s|^CAMERA2_DEVICE=.*|CAMERA2_DEVICE=\"$cam2_symlink\"|" /etc/camera-recorder/camera-mapping.conf
                log "Configuration updated!"
                
                echo
                echo "Restart the recording service:"
                echo "  sudo systemctl restart dual-camera-record.service"
            fi
        fi
        
        # Update repo config too
        if [[ -f "$(dirname $0)/../config/camera-mapping.conf" ]]; then
            echo
            echo -e "${YELLOW}Update repo config file too? (y/n)${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                sed -i "s|^CAMERA1_DEVICE=.*|CAMERA1_DEVICE=\"$cam1_symlink\"|" "$(dirname $0)/../config/camera-mapping.conf"
                sed -i "s|^CAMERA2_DEVICE=.*|CAMERA2_DEVICE=\"$cam2_symlink\"|" "$(dirname $0)/../config/camera-mapping.conf"
                log "Repo configuration updated!"
            fi
        fi
    fi
elif [[ ${#capture_devices[@]} -eq 1 ]]; then
    warn "Only one capture device found: ${capture_devices[0]}"
    echo "Connect second camera and run this script again."
else
    warn "No capture devices detected"
fi

echo
log "Camera detection complete"
