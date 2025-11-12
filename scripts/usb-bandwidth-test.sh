#!/bin/bash
#
# USB Bandwidth Analysis for Dual Camera Setup
# Analyzes USB bus capacity and camera bandwidth requirements
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  USB Bandwidth Analysis for N100 Cameras${NC}"
echo -e "${GREEN}============================================${NC}"
echo

# Check if running with appropriate permissions
if [[ ! -r "/dev/video0" ]]; then
    warn "Cannot access /dev/video0. Run with appropriate permissions or add user to video group."
fi

log "1. Analyzing USB Controllers..."
echo
lsusb -t
echo

log "2. Detecting Camera USB Connections..."
echo

# Find cameras and their USB bus info
for device in /dev/video0 /dev/video2; do
    if [[ -c "$device" ]]; then
        echo -e "${BLUE}Camera: $device${NC}"
        
        # Get device info
        udevadm info --query=all --name=$device 2>/dev/null | grep -E "(BUSNUM|DEVNUM|DEVPATH|ID_MODEL|ID_VENDOR)" || true
        
        # Get detailed v4l2 info
        if command -v v4l2-ctl &> /dev/null; then
            echo "  Driver: $(v4l2-ctl --device=$device --info 2>/dev/null | grep "Driver name" | cut -d: -f2 | xargs)"
            echo "  Card: $(v4l2-ctl --device=$device --info 2>/dev/null | grep "Card type" | cut -d: -f2 | xargs)"
            echo "  Bus: $(v4l2-ctl --device=$device --info 2>/dev/null | grep "Bus info" | cut -d: -f2 | xargs)"
        fi
        echo
    fi
done

log "3. USB Controller Information..."
echo

# List USB controllers
lspci | grep -i usb

echo
log "4. Detailed USB Controller Capabilities..."
echo

# Get detailed info about USB controllers
for controller in $(lspci | grep -i usb | cut -d' ' -f1); do
    echo -e "${BLUE}Controller: $controller${NC}"
    lspci -vv -s "$controller" 2>/dev/null | grep -E "(USB|Speed|Width|Bandwidth)" | head -20
    echo
done

log "5. Bandwidth Calculations..."
echo

# Calculate theoretical bandwidth requirements
echo -e "${BLUE}=== USB 3.0 Specifications ===${NC}"
echo "  USB 3.0 (USB 3.2 Gen 1): 5 Gbps (625 MB/s) theoretical"
echo "  USB 3.0 practical: ~400 MB/s (3.2 Gbps) due to protocol overhead"
echo "  USB 3.1 (USB 3.2 Gen 2): 10 Gbps (1.25 GB/s) theoretical"
echo

echo -e "${BLUE}=== H.264 Stream Bandwidth Requirements ===${NC}"

# Different resolution scenarios
calculate_bandwidth() {
    local resolution=$1
    local fps=$2
    local bitrate_mbps=$3
    
    # Convert to MB/s
    local bandwidth_mbs=$(echo "scale=2; $bitrate_mbps / 8" | bc)
    
    echo "  ${resolution}@${fps}fps @ ${bitrate_mbps} Mbps:"
    echo "    Single camera: ${bandwidth_mbs} MB/s"
    
    # Dual camera
    local dual=$(echo "scale=2; $bandwidth_mbs * 2" | bc)
    echo "    Dual cameras: ${dual} MB/s"
    
    # Percentage of USB 3.0 bandwidth
    local percent=$(echo "scale=1; ($dual / 400) * 100" | bc)
    echo "    USB 3.0 usage: ${percent}%"
    
    if (( $(echo "$percent < 80" | bc -l) )); then
        echo -e "    Status: ${GREEN}✓ SAFE${NC} - Well within USB 3.0 capacity"
    elif (( $(echo "$percent < 95" | bc -l) )); then
        echo -e "    Status: ${YELLOW}⚠ CAUTION${NC} - High USB bandwidth usage"
    else
        echo -e "    Status: ${RED}✗ RISK${NC} - May exceed USB bandwidth"
    fi
    echo
}

echo
echo -e "${BLUE}Scenario 1: 4K@60fps (Original)${NC}"
calculate_bandwidth "3840x2160" "60" "20"

echo -e "${BLUE}Scenario 2: 1440p@30fps (Current Configuration)${NC}"
calculate_bandwidth "2560x1440" "30" "12"

echo -e "${BLUE}Scenario 3: 1440p@60fps (Alternative)${NC}"
calculate_bandwidth "2560x1440" "60" "15"

echo -e "${BLUE}Scenario 4: 1080p@60fps (Conservative)${NC}"
calculate_bandwidth "1920x1080" "60" "8"

log "6. Current Camera Capabilities..."
echo

for device in /dev/video0 /dev/video2; do
    if [[ -c "$device" ]] && command -v v4l2-ctl &> /dev/null; then
        echo -e "${BLUE}Camera: $device${NC}"
        echo "Supported H264 formats and framerates:"
        v4l2-ctl --device=$device --list-formats-ext 2>/dev/null | grep -A20 "H264" | grep -E "(Size|Interval)" || echo "  No H264 support detected"
        echo
    fi
done

log "7. Real-time Bandwidth Monitoring..."
echo

if command -v usbutils &> /dev/null || command -v usb-devices &> /dev/null; then
    info "Use 'usb-devices' for detailed USB device information"
fi

echo -e "${BLUE}To monitor real-time USB bandwidth:${NC}"
echo "  1. Install usbmon: sudo modprobe usbmon"
echo "  2. Monitor with: sudo cat /sys/kernel/debug/usb/usbmon/0u"
echo "  3. Or use wireshark with usbmon"
echo

log "8. Recommendations..."
echo

echo -e "${GREEN}✓ Current Configuration (1440p@30fps):${NC}"
echo "  - Bandwidth: ~3 MB/s total (0.75% of USB 3.0)"
echo "  - Status: EXCELLENT - Very low USB bandwidth usage"
echo "  - Can easily handle both cameras on single USB controller"
echo

echo -e "${YELLOW}Alternative Configurations:${NC}"
echo "  - 1440p@60fps: ~3.75 MB/s (0.94% USB 3.0) - Still safe"
echo "  - 4K@30fps: ~5 MB/s (1.25% USB 3.0) - Safe"
echo "  - 4K@60fps: ~10 MB/s (2.5% USB 3.0) - Safe, but higher CPU load"
echo

echo -e "${BLUE}Intel N100 USB Controllers:${NC}"
echo "  - Typically has 2-4 USB 3.2 Gen 2 controllers (10 Gbps each)"
echo "  - Can handle multiple 4K cameras simultaneously"
echo "  - Bottleneck is more likely to be:"
echo "    • Camera H264 encoding quality/bitrate"
echo "    • CPU capacity for transcoding to HEVC"
echo "    • Storage write speed"
echo

log "9. USB Topology Check..."
echo

# Check which USB controller each camera is on
echo "Checking if cameras share the same USB controller..."
echo

for device in /dev/video0 /dev/video2; do
    if [[ -c "$device" ]]; then
        devpath=$(udevadm info --query=property --name=$device 2>/dev/null | grep "DEVPATH=" | cut -d= -f2)
        bus=$(echo "$devpath" | grep -oP 'usb\d+' | head -1)
        port=$(echo "$devpath" | grep -oP '/\d+-\d+' | head -1)
        
        echo -e "${BLUE}$device:${NC}"
        echo "  Bus: $bus"
        echo "  Port: $port"
        echo "  Full path: $devpath"
        echo
    fi
done

log "10. Testing Actual Stream Bandwidth..."
echo

test_camera_bandwidth() {
    local device=$1
    local resolution=$2
    local fps=$3
    
    if [[ ! -c "$device" ]]; then
        warn "$device not found"
        return
    fi
    
    if ! command -v v4l2-ctl &> /dev/null; then
        warn "v4l2-ctl not installed, skipping bandwidth test"
        return
    fi
    
    echo -e "${BLUE}Testing $device @ $resolution @ ${fps}fps...${NC}"
    
    # Capture 5 seconds and measure bandwidth
    local temp_file="/tmp/bandwidth_test_$(basename $device).h264"
    
    # Try to capture with timeout
    timeout 5 v4l2-ctl --device=$device \
        --set-fmt-video=width=$(echo $resolution | cut -dx -f1),height=$(echo $resolution | cut -dx -f2),pixelformat=H264 \
        --stream-mmap --stream-to=$temp_file 2>/dev/null || true
    
    if [[ -f "$temp_file" ]]; then
        local size=$(stat -f%z "$temp_file" 2>/dev/null || stat -c%s "$temp_file" 2>/dev/null)
        local size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
        local bandwidth_mbps=$(echo "scale=2; ($size * 8 / 1024 / 1024) / 5" | bc)
        
        echo "  Captured: ${size_mb} MB in 5 seconds"
        echo "  Bandwidth: ${bandwidth_mbps} Mbps"
        
        rm -f "$temp_file"
    else
        warn "Could not capture test stream from $device"
    fi
    echo
}

# Test both cameras if available
info "Testing actual bandwidth usage (requires cameras to be idle)..."
test_camera_bandwidth "/dev/video0" "2560x1440" "30"
test_camera_bandwidth "/dev/video2" "2560x1440" "30"

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Analysis Complete${NC}"
echo -e "${GREEN}============================================${NC}"
echo
echo -e "${GREEN}CONCLUSION:${NC}"
echo "  1440p@30fps H.264 from both cameras uses minimal USB bandwidth"
echo "  Intel N100's USB 3.2 controllers can easily handle this load"
echo "  No USB bandwidth concerns for current configuration"
echo
