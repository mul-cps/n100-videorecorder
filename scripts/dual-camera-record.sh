#!/bin/bash
#
# Dual Camera QSV Recording Script
# Optimized for Intel N100 with Intel Quick Sync Video
#

set -e

# Source configuration
CONFIG_FILE="/etc/camera-recorder/camera-mapping.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default configuration if not loaded
CAMERA1_DEVICE="${CAMERA1_DEVICE:-/dev/video0}"
CAMERA2_DEVICE="${CAMERA2_DEVICE:-/dev/video2}"
CAMERA1_RESOLUTION="${CAMERA1_RESOLUTION:-3840x2160}"
CAMERA2_RESOLUTION="${CAMERA2_RESOLUTION:-3840x2160}"
CAMERA1_FRAMERATE="${CAMERA1_FRAMERATE:-30}"
CAMERA2_FRAMERATE="${CAMERA2_FRAMERATE:-30}"
CAMERA1_FORMAT="${CAMERA1_FORMAT:-h264}"
CAMERA2_FORMAT="${CAMERA2_FORMAT:-h264}"
ENCODING_PRESET="${ENCODING_PRESET:-medium}"
ENCODING_QUALITY="${ENCODING_QUALITY:-28}"
SEGMENT_TIME="${SEGMENT_TIME:-3600}"
RECORDINGS_BASE="${RECORDINGS_BASE:-/storage/recordings}"

# Runtime variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Try to find the correct FFmpeg binary
if [[ -x "/usr/lib/jellyfin-ffmpeg/ffmpeg7" ]]; then
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg7"
elif [[ -x "/usr/lib/jellyfin-ffmpeg/ffmpeg6" ]]; then
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg6"
else
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"
fi
LOG_DIR="/var/log/camera-recorder"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_DIR/dual-camera.log"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_DIR/dual-camera.log"
}

# Ensure iHD driver for better N100 performance
export LIBVA_DRIVER_NAME=iHD

# Create directories
mkdir -p "$RECORDINGS_BASE"/{cam1,cam2}
mkdir -p "$LOG_DIR"

# Check if cameras are available
if [[ ! -c "$CAMERA1_DEVICE" ]]; then
    error "Camera 1 device $CAMERA1_DEVICE not found"
    exit 1
fi

if [[ ! -c "$CAMERA2_DEVICE" ]]; then
    error "Camera 2 device $CAMERA2_DEVICE not found"
    exit 1
fi

log "Starting dual camera recording..."
log "Camera 1: $CAMERA1_DEVICE @ ${CAMERA1_RESOLUTION}@${CAMERA1_FRAMERATE}fps"
log "Camera 2: $CAMERA2_DEVICE @ ${CAMERA2_RESOLUTION}@${CAMERA2_FRAMERATE}fps"

# Camera 1 - QSV H.265 Recording
log "Starting Camera 1 recording process..."

# Build FFmpeg command based on input format
if [[ "$CAMERA1_FORMAT" == "h264" ]]; then
    # H264 input - decode and re-encode with QSV (simpler approach without hwupload filters)
    "$FFMPEG" \
        -f v4l2 \
        -input_format h264 \
        -video_size "$CAMERA1_RESOLUTION" \
        -framerate "$CAMERA1_FRAMERATE" \
        -i "$CAMERA1_DEVICE" \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam1/cam1_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera1-qsv.log" &
elif [[ "$CAMERA1_FORMAT" == "mjpeg" ]]; then
    # MJPEG input
    "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size "$CAMERA1_RESOLUTION" \
        -framerate "$CAMERA1_FRAMERATE" \
        -i "$CAMERA1_DEVICE" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -look_ahead 1 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam1/cam1_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera1-qsv.log" &
else
    # YUYV or other raw format
    "$FFMPEG" \
        -f v4l2 \
        -video_size "$CAMERA1_RESOLUTION" \
        -framerate "$CAMERA1_FRAMERATE" \
        -i "$CAMERA1_DEVICE" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -look_ahead 1 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam1/cam1_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera1-qsv.log" &
fi

CAM1_PID=$!
log "Camera 1 recording started with PID: $CAM1_PID"

# Camera 2 - QSV H.265 Recording  
log "Starting Camera 2 recording process..."

# Build FFmpeg command based on input format
if [[ "$CAMERA2_FORMAT" == "h264" ]]; then
    # H264 input - decode and re-encode with QSV (simpler approach without hwupload filters)
    "$FFMPEG" \
        -f v4l2 \
        -input_format h264 \
        -video_size "$CAMERA2_RESOLUTION" \
        -framerate "$CAMERA2_FRAMERATE" \
        -i "$CAMERA2_DEVICE" \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam2/cam2_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera2-qsv.log" &
elif [[ "$CAMERA2_FORMAT" == "mjpeg" ]]; then
    # MJPEG input
    "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size "$CAMERA2_RESOLUTION" \
        -framerate "$CAMERA2_FRAMERATE" \
        -i "$CAMERA2_DEVICE" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -look_ahead 1 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam2/cam2_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera2-qsv.log" &
else
    # YUYV or other raw format
    "$FFMPEG" \
        -f v4l2 \
        -video_size "$CAMERA2_RESOLUTION" \
        -framerate "$CAMERA2_FRAMERATE" \
        -i "$CAMERA2_DEVICE" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -look_ahead 1 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$RECORDINGS_BASE/cam2/cam2_%Y%m%d_%H%M%S.mp4" \
        2>&1 | tee -a "$LOG_DIR/camera2-qsv.log" &
fi

CAM2_PID=$!
log "Camera 2 recording started with PID: $CAM2_PID"

# Function to handle shutdown gracefully
shutdown() {
    log "Received shutdown signal, stopping recordings..."
    
    if kill -0 $CAM1_PID 2>/dev/null; then
        log "Stopping Camera 1 (PID: $CAM1_PID)"
        kill -TERM $CAM1_PID
    fi
    
    if kill -0 $CAM2_PID 2>/dev/null; then
        log "Stopping Camera 2 (PID: $CAM2_PID)"
        kill -TERM $CAM2_PID
    fi
    
    # Wait for processes to finish
    wait $CAM1_PID 2>/dev/null || true
    wait $CAM2_PID 2>/dev/null || true
    
    log "Recording stopped cleanly"
    exit 0
}

# Set up signal handlers
trap shutdown SIGTERM SIGINT SIGQUIT

# Monitor both processes
monitor_recordings() {
    while true; do
        sleep 30
        
        # Check if both processes are still running
        if ! kill -0 $CAM1_PID 2>/dev/null; then
            error "Camera 1 process died unexpectedly"
            break
        fi
        
        if ! kill -0 $CAM2_PID 2>/dev/null; then
            error "Camera 2 process died unexpectedly"
            break
        fi
        
        # Log disk usage every 10 minutes
        if (( $(date +%s) % 600 == 0 )); then
            local disk_usage=$(df "$RECORDINGS_BASE" | tail -1 | awk '{print $5}' | sed 's/%//')
            log "Disk usage: ${disk_usage}% - Available: $(df -h "$RECORDINGS_BASE" | tail -1 | awk '{print $4}')"
            
            # Stop recording if disk usage exceeds 95%
            if [[ $disk_usage -gt 95 ]]; then
                error "Disk usage critical (${disk_usage}%) - stopping recording"
                shutdown
            fi
        fi
    done
}

# Start monitoring in background
monitor_recordings &
MONITOR_PID=$!

log "Recording started successfully. Monitoring enabled."
log "To stop recording, run: systemctl stop dual-camera-record"

# Wait for both camera processes
wait $CAM1_PID
wait $CAM2_PID

# Stop monitoring
kill $MONITOR_PID 2>/dev/null || true

log "Recording session ended"
