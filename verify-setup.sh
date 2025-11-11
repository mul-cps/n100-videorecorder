#!/bin/bash
#
# Final Setup Verification Script
# Run this after deployment to verify everything is working correctly
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${BLUE}[ℹ]${NC} $1"; }

TEST_PASSED=0
TEST_FAILED=0

pass_test() {
    TEST_PASSED=$((TEST_PASSED + 1))
    log "$1"
}

fail_test() {
    TEST_FAILED=$((TEST_FAILED + 1))
    error "$1"
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   N100 Video Recorder Setup Verification${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Test 1: Check Intel QSV Support
info "Testing Intel QSV support..."
export LIBVA_DRIVER_NAME=iHD
if vainfo --display drm --device /dev/dri/renderD128 &>/dev/null; then
    pass_test "VA-API is working with iHD driver"
else
    fail_test "VA-API not working - check intel-media-va-driver-non-free"
fi

if /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_qsv"; then
    pass_test "QSV HEVC encoder available"
else
    fail_test "QSV HEVC encoder not found"
fi

# Test 2: Check Camera Devices
info "Testing camera devices..."
camera_count=0
for device in /dev/video0 /dev/video2; do
    if [[ -c "$device" ]]; then
        camera_count=$((camera_count + 1))
        pass_test "Camera device $device found"
        
        # Test basic capture
        if timeout 3s /usr/lib/jellyfin-ffmpeg/ffmpeg \
            -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 15 \
            -i "$device" -frames:v 1 -y "/tmp/test_$(basename "$device").jpg" &>/dev/null; then
            pass_test "Camera $device capture test successful"
            rm -f "/tmp/test_$(basename "$device").jpg"
        else
            fail_test "Camera $device capture test failed"
        fi
    else
        fail_test "Camera device $device not found"
    fi
done

if [[ $camera_count -ge 2 ]]; then
    pass_test "Found $camera_count camera devices"
else
    fail_test "Only found $camera_count camera devices (need 2)"
fi

# Test 3: Check Storage
info "Testing storage configuration..."
if [[ -d "/storage/recordings" ]]; then
    pass_test "Recordings directory exists"
    
    # Check write permissions
    if touch "/storage/recordings/write_test" 2>/dev/null; then
        rm -f "/storage/recordings/write_test"
        pass_test "Storage directory is writable"
    else
        fail_test "Storage directory is not writable"
    fi
    
    # Check available space
    available_gb=$(df /storage/recordings | tail -1 | awk '{print int($4/1024/1024)}')
    if [[ $available_gb -gt 50 ]]; then
        pass_test "Adequate storage space available (${available_gb}GB)"
    else
        warn "Limited storage space (${available_gb}GB) - consider adding more"
    fi
else
    fail_test "Recordings directory /storage/recordings not found"
fi

# Test 4: Check Configuration Files
info "Testing configuration files..."
config_files=(
    "/etc/camera-recorder/camera-mapping.conf"
    "/etc/systemd/system/dual-camera-record.service"
    "/etc/udev/rules.d/99-camera-mapping.rules"
)

for config_file in "${config_files[@]}"; do
    if [[ -f "$config_file" ]]; then
        pass_test "Configuration file exists: $(basename "$config_file")"
    else
        fail_test "Configuration file missing: $config_file"
    fi
done

# Test 5: Check System Services
info "Testing system services..."
if systemctl is-enabled dual-camera-record &>/dev/null; then
    pass_test "Recording service is enabled"
else
    fail_test "Recording service is not enabled"
fi

# Test 6: Check Network Configuration
info "Testing network configuration..."
if [[ -f "/etc/netplan/50-wifi.yaml" ]]; then
    pass_test "WiFi configuration file exists"
else
    warn "WiFi configuration file not found - run setup-wifi.sh"
fi

# Check if connected to network
if ping -c 1 8.8.8.8 &>/dev/null; then
    pass_test "Internet connectivity working"
else
    warn "No internet connectivity - check network configuration"
fi

# Test 7: Quick QSV Encoding Test
info "Running QSV encoding test..."
if [[ -c "/dev/video0" ]]; then
    if timeout 5s /usr/lib/jellyfin-ffmpeg/ffmpeg \
        -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 15 \
        -i /dev/video0 \
        -init_hw_device qsv=hw -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv -preset fast -global_quality 30 \
        -frames:v 30 -y /tmp/qsv_verification_test.mp4 2>/tmp/qsv_test.log; then
        
        if [[ -f "/tmp/qsv_verification_test.mp4" ]]; then
            file_size=$(du -h /tmp/qsv_verification_test.mp4 | cut -f1)
            pass_test "QSV encoding test successful (output: $file_size)"
            rm -f /tmp/qsv_verification_test.mp4
        else
            fail_test "QSV encoding test failed - no output file"
        fi
    else
        fail_test "QSV encoding test failed - check logs at /tmp/qsv_test.log"
    fi
else
    warn "No camera available for QSV encoding test"
fi

# Test 8: Check Log Directories
info "Testing log directories..."
log_dirs=("/var/log/camera-recorder")

for log_dir in "${log_dirs[@]}"; do
    if [[ -d "$log_dir" ]]; then
        pass_test "Log directory exists: $log_dir"
    else
        fail_test "Log directory missing: $log_dir"
    fi
done

echo
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}             Test Summary${NC}"
echo -e "${BLUE}============================================${NC}"

if [[ $TEST_FAILED -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed! ($TEST_PASSED/$((TEST_PASSED + TEST_FAILED)))${NC}"
    echo -e "${GREEN}Your N100 video recorder is ready for deployment!${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Configure WiFi credentials: sudo nano /etc/netplan/50-wifi.yaml"
    echo "2. Apply network config: sudo netplan apply"
    echo "3. Start recording: sudo systemctl start dual-camera-record"
    echo "4. Monitor status: sudo systemctl status dual-camera-record"
    echo
    exit_code=0
else
    echo -e "${RED}❌ $TEST_FAILED tests failed, $TEST_PASSED tests passed${NC}"
    echo -e "${RED}Please fix the issues above before proceeding.${NC}"
    echo
    echo -e "${YELLOW}Common fixes:${NC}"
    echo "• Install missing drivers: sudo ./deploy.sh"
    echo "• Check camera connections: lsusb && v4l2-ctl --list-devices"
    echo "• Verify storage permissions: sudo chown -R \$USER:\$USER /storage"
    echo "• Test QSV manually: sudo ./scripts/test-qsv.sh"
    echo
    exit_code=1
fi

echo -e "${BLUE}For detailed troubleshooting, see DEPLOYMENT.md${NC}"
exit $exit_code
