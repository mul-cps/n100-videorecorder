#!/bin/bash
#
# Test QSV Support Script
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${GREEN}Intel QSV Support Test${NC}"
echo "========================"

# Check Intel GPU
echo "Intel GPU Detection:"
if lspci | grep -i "VGA.*Intel" &>/dev/null; then
    lspci | grep -i "VGA.*Intel"
    log "Intel GPU detected"
else
    error "No Intel GPU found"
    exit 1
fi

# Check VA-API
echo
echo "VA-API Test:"
export LIBVA_DRIVER_NAME=iHD
if vainfo --display drm --device /dev/dri/renderD128 &>/dev/null; then
    log "VA-API is working with iHD driver"
    vainfo --display drm --device /dev/dri/renderD128 2>/dev/null | grep -E "(VAProfile|VAEntrypoint)" | head -10
else
    error "VA-API not working - check intel-media-va-driver-non-free"
fi

# Check FFmpeg QSV support
echo
echo "FFmpeg QSV Encoders:"
if /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders 2>/dev/null | grep qsv; then
    log "QSV encoders available"
else
    error "QSV encoders not found - check jellyfin-ffmpeg installation"
fi

# Quick encode test
echo
echo "QSV Encoding Test:"
if [[ -c "/dev/video0" ]]; then
    log "Testing QSV encoding from camera..."
    
    timeout 5s /usr/lib/jellyfin-ffmpeg/ffmpeg \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1280x720 \
        -framerate 15 \
        -i /dev/video0 \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset fast \
        -global_quality 30 \
        -frames:v 30 \
        -y /tmp/qsv_test.mp4 2>/tmp/qsv_test.log
    
    if [[ -f "/tmp/qsv_test.mp4" ]]; then
        size=$(du -h /tmp/qsv_test.mp4 | cut -f1)
        log "QSV encoding test PASSED - Output: $size"
        rm -f /tmp/qsv_test.mp4
    else
        error "QSV encoding test FAILED"
        cat /tmp/qsv_test.log
    fi
else
    warn "No camera device found for QSV test"
fi

echo
log "QSV test complete!"
