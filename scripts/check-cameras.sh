#!/bin/bash
#
# Check Camera Status Script
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${GREEN}Camera System Status Check${NC}"
echo "=================================="

# Check service status
echo "Service Status:"
if systemctl is-active --quiet dual-camera-record; then
    log "Recording service is ACTIVE"
else
    warn "Recording service is INACTIVE"
fi

# Check camera devices
echo
echo "Camera Devices:"
for device in /dev/video*; do
    if [[ -c "$device" ]]; then
        echo "  Found: $device"
        
        # Get device info
        if command -v v4l2-ctl &> /dev/null; then
            info=$(v4l2-ctl --device="$device" --info 2>/dev/null | grep "Card" | cut -d: -f2 | xargs)
            echo "    Info: $info"
        fi
    fi
done

# Check disk usage
echo
echo "Storage Status:"
if [[ -d "/storage/recordings" ]]; then
    df -h /storage/recordings
else
    df -h /
fi

# Check recent recordings
echo
echo "Recent Recordings:"
for cam in cam1 cam2; do
    cam_dir="/storage/recordings/$cam"
    if [[ -d "$cam_dir" ]]; then
        recent=$(ls -t "$cam_dir"/*.mp4 2>/dev/null | head -1)
        if [[ -n "$recent" ]]; then
            size=$(du -h "$recent" | cut -f1)
            age=$(stat -c %y "$recent" | cut -d. -f1)
            echo "  $cam: $(basename "$recent") ($size, $age)"
        else
            echo "  $cam: No recordings found"
        fi
    fi
done

# Check system resources
echo
echo "System Resources:"
echo "  CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
echo "  Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')"

# Check QSV support
echo
echo "QSV Status:"
if vainfo --display drm --device /dev/dri/renderD128 &>/dev/null; then
    log "VA-API is working"
else
    error "VA-API not working"
fi

if /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_qsv; then
    log "QSV HEVC encoder available"
else
    error "QSV HEVC encoder not available"
fi

echo
echo "Check complete!"
