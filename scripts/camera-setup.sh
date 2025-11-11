#!/bin/bash
#
# Camera Setup Script - Detect and configure USB cameras
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

detect_cameras() {
    log "Detecting USB cameras..."
    
    # List video devices
    echo "Available video devices:"
    ls -la /dev/video* 2>/dev/null || {
        error "No video devices found!"
        exit 1
    }
    
    echo
    echo "USB camera details:"
    for device in /dev/video*; do
        if [[ -c "$device" ]]; then
            device_num=$(basename "$device" | sed 's/video//')
            
            # Get device info using v4l2-ctl
            if command -v v4l2-ctl &> /dev/null; then
                echo "Device: $device"
                v4l2-ctl --device="$device" --info 2>/dev/null | grep -E "(Driver|Card|Bus info)" || echo "  Info not available"
                
                # Check supported formats
                echo "  Supported formats:"
                v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -E "(MJPEG|YUYV|H264)" | head -3 || echo "    No suitable formats found"
                echo
            fi
        fi
    done
}

test_camera_capture() {
    local device="$1"
    local output_file="$2"
    
    log "Testing capture from $device..."
    
    # Test basic capture capability
    timeout 5s /usr/lib/jellyfin-ffmpeg/ffmpeg \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i "$device" \
        -frames:v 1 \
        -y "$output_file" &>/dev/null
    
    if [[ -f "$output_file" ]]; then
        log "Camera $device: Capture test PASSED"
        rm -f "$output_file"
        return 0
    else
        warn "Camera $device: Capture test FAILED"
        return 1
    fi
}

create_camera_mapping() {
    log "Creating persistent camera mapping..."
    
    local mapping_file="/etc/camera-recorder/camera-mapping.conf"
    mkdir -p "$(dirname "$mapping_file")"
    
    cat > "$mapping_file" << 'EOF'
# Camera mapping configuration
# Edit this file to map cameras to specific devices

# Camera 1 - Primary camera
CAMERA1_DEVICE="/dev/video0"
CAMERA1_NAME="Primary Camera"
CAMERA1_RESOLUTION="3840x2160"
CAMERA1_FRAMERATE="30"

# Camera 2 - Secondary camera  
CAMERA2_DEVICE="/dev/video2"
CAMERA2_NAME="Secondary Camera"
CAMERA2_RESOLUTION="3840x2160"
CAMERA2_FRAMERATE="30"

# Encoding settings
ENCODING_PRESET="medium"
ENCODING_QUALITY="28"
SEGMENT_TIME="3600"  # 1 hour segments

# Storage settings
RECORDINGS_BASE="/storage/recordings"
CLEANUP_DAYS="30"
EOF
    
    log "Camera mapping created at $mapping_file"
    log "Please edit this file to match your camera setup"
}

generate_udev_rules() {
    log "Generating USB camera udev rules..."
    
    local udev_file="/tmp/99-camera-mapping.rules"
    
    cat > "$udev_file" << 'EOF'
# USB Camera persistent device mapping
# This file ensures cameras maintain consistent /dev/videoX assignments

# Match USB cameras by vendor/product ID and assign specific device nodes
# Update ATTR{idVendor} and ATTR{idProduct} with your camera's actual IDs

# Example for common USB cameras:
# SUBSYSTEM=="video4linux", ATTR{idVendor}=="0c45", ATTR{idProduct}=="636d", SYMLINK+="video-cam1"
# SUBSYSTEM=="video4linux", ATTR{idVendor}=="046d", ATTR{idProduct}=="085b", SYMLINK+="video-cam2"

# Generic fallback rules - creates symlinks based on USB bus position
# These may change if you plug cameras into different USB ports
KERNEL=="video[0-9]*", SUBSYSTEM=="video4linux", ATTRS{busnum}=="1", ATTRS{devnum}=="*", SYMLINK+="video-usb1-%n"
KERNEL=="video[0-9]*", SUBSYSTEM=="video4linux", ATTRS{busnum}=="2", ATTRS{devnum}=="*", SYMLINK+="video-usb2-%n"
KERNEL=="video[0-9]*", SUBSYSTEM=="video4linux", ATTRS{busnum}=="3", ATTRS{devnum}=="*", SYMLINK+="video-usb3-%n"
KERNEL=="video[0-9]*", SUBSYSTEM=="video4linux", ATTRS{busnum}=="4", ATTRS{devnum}=="*", SYMLINK+="video-usb4-%n"
EOF
    
    echo "Generated udev rules template at $udev_file"
    echo "To create specific rules for your cameras, run:"
    echo "  lsusb"
    echo "  udevadm info -a -p \$(udevadm info -q path -n /dev/video0)"
    echo "Then edit $udev_file with your camera's vendor/product IDs"
}

check_qsv_support() {
    log "Checking Intel QSV support..."
    
    # Check if Intel GPU is present
    if ! lspci | grep -i "VGA.*Intel" &>/dev/null; then
        warn "Intel GPU not detected - QSV may not be available"
        return 1
    fi
    
    # Check if VA-API is working
    if ! vainfo --display drm --device /dev/dri/renderD128 &>/dev/null; then
        warn "VA-API not working - install intel-media-va-driver-non-free"
        return 1
    fi
    
    # Check if QSV encoders are available in FFmpeg
    if ! /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_qsv\|hevc_qsv"; then
        warn "QSV encoders not found - install jellyfin-ffmpeg"
        return 1
    fi
    
    log "Intel QSV support is available!"
    return 0
}

test_4k_capability() {
    log "Testing 4K capture capability..."
    
    for device in /dev/video0 /dev/video2; do
        if [[ -c "$device" ]]; then
            log "Testing 4K on $device..."
            
            # Test if device supports 4K MJPEG
            if v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -A5 "MJPEG" | grep -q "3840x2160"; then
                log "$device supports 4K MJPEG - GOOD!"
                
                # Quick test capture
                timeout 3s /usr/lib/jellyfin-ffmpeg/ffmpeg \
                    -f v4l2 \
                    -input_format mjpeg \
                    -video_size 3840x2160 \
                    -framerate 15 \
                    -i "$device" \
                    -frames:v 1 \
                    -y "/tmp/4k_test_$(basename "$device").jpg" &>/dev/null
                
                if [[ -f "/tmp/4k_test_$(basename "$device").jpg" ]]; then
                    log "$device: 4K capture test PASSED"
                    rm -f "/tmp/4k_test_$(basename "$device").jpg"
                else
                    warn "$device: 4K capture test FAILED"
                fi
            else
                warn "$device does not support 4K MJPEG"
            fi
        fi
    done
}

main() {
    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}    Camera Setup & Detection${NC}"
    echo -e "${GREEN}==================================${NC}"
    echo
    
    detect_cameras
    echo
    
    check_qsv_support
    echo
    
    test_4k_capability
    echo
    
    create_camera_mapping
    echo
    
    generate_udev_rules
    echo
    
    echo -e "${GREEN}Camera setup complete!${NC}"
    echo
    echo "Next steps:"
    echo "1. Edit /etc/camera-recorder/camera-mapping.conf"
    echo "2. Configure udev rules if needed: /tmp/99-camera-mapping.rules"
    echo "3. Run camera test: camera-test.sh"
    echo "4. Start recording service: systemctl start dual-camera-record"
}

main "$@"
