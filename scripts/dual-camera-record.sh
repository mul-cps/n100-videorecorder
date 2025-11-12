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
ENCODING_CODEC="${ENCODING_CODEC:-hevc_qsv}"
ENCODING_PRESET="${ENCODING_PRESET:-medium}"
ENCODING_QUALITY="${ENCODING_QUALITY:-28}"
SEGMENT_TIME="${SEGMENT_TIME:-3600}"
RECORDINGS_BASE="${RECORDINGS_BASE:-/storage/recordings}"
LOOKAHEAD_ENABLED="${LOOKAHEAD_ENABLED:-1}"
BITRATE_MODE="${BITRATE_MODE:-VBR}"
TARGET_BITRATE="${TARGET_BITRATE:-15000}"
MAX_BITRATE="${MAX_BITRATE:-20000}"
GOP_SIZE="${GOP_SIZE:-60}"
REF_FRAMES="${REF_FRAMES:-3}"

# Runtime variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Try to find the correct FFmpeg binary
if [[ -x "/usr/lib/jellyfin-ffmpeg/ffmpeg" ]]; then
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"
elif [[ -x "/usr/local/bin/ffmpeg-qsv" ]]; then
    FFMPEG="/usr/local/bin/ffmpeg-qsv"
else
    FFMPEG="ffmpeg"
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
    if [[ "$ENCODING_CODEC" == "copy" ]]; then
        # Stream copy mode - no transcoding, just remux to MP4 segments
        "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size "$CAMERA1_RESOLUTION" \
            -framerate "$CAMERA1_FRAMERATE" \
            -i "$CAMERA1_DEVICE" \
            -c:v copy \
            -f segment \
            -segment_time "$SEGMENT_TIME" \
            -segment_format mp4 \
            -segment_format_options movflags=+faststart+frag_keyframe \
            -reset_timestamps 1 \
            -strftime 1 \
            "$RECORDINGS_BASE/cam1/cam1_%Y%m%d_%H%M%S.mp4" \
            2>&1 | tee -a "$LOG_DIR/camera1-qsv.log" &
    else
        # H264 input - decode and re-encode with QSV
        "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size "$CAMERA1_RESOLUTION" \
            -framerate "$CAMERA1_FRAMERATE" \
            -i "$CAMERA1_DEVICE" \
            -c:v "$ENCODING_CODEC" \
            -preset "$ENCODING_PRESET" \
            -global_quality "$ENCODING_QUALITY" \
            -look_ahead "$LOOKAHEAD_ENABLED" \
            -b:v "${TARGET_BITRATE}k" \
            -maxrate "${MAX_BITRATE}k" \
            -g "$GOP_SIZE" \
            -refs "$REF_FRAMES" \
            -bf 3 \
            -vsync vfr \
            -fps_mode passthrough \
            -f segment \
            -segment_time "$SEGMENT_TIME" \
            -segment_format mp4 \
            -segment_format_options movflags=+faststart+frag_keyframe \
            -flush_packets 0 \
            -reset_timestamps 1 \
            -strftime 1 \
            "$RECORDINGS_BASE/cam1/cam1_%Y%m%d_%H%M%S.mp4" \
            2>&1 | tee -a "$LOG_DIR/camera1-qsv.log" &
    fi
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
        -look_ahead "$LOOKAHEAD_ENABLED" \
        -b:v "${TARGET_BITRATE}k" \
        -maxrate "${MAX_BITRATE}k" \
        -g "$GOP_SIZE" \
        -refs "$REF_FRAMES" \
        -bf 3 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -segment_format_options movflags=+faststart+frag_keyframe \
        -flush_packets 0 \
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
        -look_ahead "$LOOKAHEAD_ENABLED" \
        -b:v "${TARGET_BITRATE}k" \
        -maxrate "${MAX_BITRATE}k" \
        -g "$GOP_SIZE" \
        -refs "$REF_FRAMES" \
        -bf 3 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -segment_format_options movflags=+faststart+frag_keyframe \
        -flush_packets 0 \
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
    if [[ "$ENCODING_CODEC" == "copy" ]]; then
        # Stream copy mode - no transcoding, just remux to MP4 segments
        "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size "$CAMERA2_RESOLUTION" \
            -framerate "$CAMERA2_FRAMERATE" \
            -i "$CAMERA2_DEVICE" \
            -c:v copy \
            -f segment \
            -segment_time "$SEGMENT_TIME" \
            -segment_format mp4 \
            -segment_format_options movflags=+faststart+frag_keyframe \
            -reset_timestamps 1 \
            -strftime 1 \
            "$RECORDINGS_BASE/cam2/cam2_%Y%m%d_%H%M%S.mp4" \
            2>&1 | tee -a "$LOG_DIR/camera2-qsv.log" &
    else
        # H264 input - decode and re-encode with QSV
        "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size "$CAMERA2_RESOLUTION" \
            -framerate "$CAMERA2_FRAMERATE" \
            -i "$CAMERA2_DEVICE" \
            -c:v "$ENCODING_CODEC" \
            -preset "$ENCODING_PRESET" \
            -global_quality "$ENCODING_QUALITY" \
            -look_ahead "$LOOKAHEAD_ENABLED" \
            -b:v "${TARGET_BITRATE}k" \
            -maxrate "${MAX_BITRATE}k" \
            -g "$GOP_SIZE" \
            -refs "$REF_FRAMES" \
            -bf 3 \
            -vsync vfr \
            -fps_mode passthrough \
            -f segment \
            -segment_time "$SEGMENT_TIME" \
            -segment_format mp4 \
            -segment_format_options movflags=+faststart+frag_keyframe \
            -flush_packets 0 \
            -reset_timestamps 1 \
            -strftime 1 \
            "$RECORDINGS_BASE/cam2/cam2_%Y%m%d_%H%M%S.mp4" \
            2>&1 | tee -a "$LOG_DIR/camera2-qsv.log" &
    fi
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
        -look_ahead "$LOOKAHEAD_ENABLED" \
        -b:v "${TARGET_BITRATE}k" \
        -maxrate "${MAX_BITRATE}k" \
        -g "$GOP_SIZE" \
        -refs "$REF_FRAMES" \
        -bf 3 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -segment_format_options movflags=+faststart+frag_keyframe \
        -flush_packets 0 \
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
        -look_ahead "$LOOKAHEAD_ENABLED" \
        -b:v "${TARGET_BITRATE}k" \
        -maxrate "${MAX_BITRATE}k" \
        -g "$GOP_SIZE" \
        -refs "$REF_FRAMES" \
        -bf 3 \
        -f segment \
        -segment_time "$SEGMENT_TIME" \
        -segment_format mp4 \
        -segment_format_options movflags=+faststart+frag_keyframe \
        -flush_packets 0 \
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
    
    # Stop the monitoring process first
    if [[ -n "$MONITOR_PID" ]] && kill -0 $MONITOR_PID 2>/dev/null; then
        kill -TERM $MONITOR_PID 2>/dev/null || true
    fi
    
    # Send SIGINT to FFmpeg processes for graceful shutdown
    # FFmpeg will properly finalize the video files when receiving SIGINT
    if kill -0 $CAM1_PID 2>/dev/null; then
        log "Stopping Camera 1 (PID: $CAM1_PID)"
        kill -INT $CAM1_PID 2>/dev/null
    fi
    
    if kill -0 $CAM2_PID 2>/dev/null; then
        log "Stopping Camera 2 (PID: $CAM2_PID)"
        kill -INT $CAM2_PID 2>/dev/null
    fi
    
    # Give FFmpeg time to close files properly
    local timeout=10
    local elapsed=0
    
    log "Waiting for FFmpeg processes to finalize recordings..."
    
    while (( elapsed < timeout )); do
        local cam1_alive=0
        local cam2_alive=0
        
        kill -0 $CAM1_PID 2>/dev/null && cam1_alive=1
        kill -0 $CAM2_PID 2>/dev/null && cam2_alive=1
        
        if [[ $cam1_alive -eq 0 ]] && [[ $cam2_alive -eq 0 ]]; then
            log "Both cameras stopped gracefully"
            break
        fi
        
        sleep 1
        ((elapsed++))
        
        # Log progress
        if (( elapsed % 3 == 0 )); then
            local status=""
            [[ $cam1_alive -eq 1 ]] && status+="Camera1 "
            [[ $cam2_alive -eq 1 ]] && status+="Camera2 "
            [[ -n "$status" ]] && log "Waiting for: $status(${elapsed}s)"
        fi
    done
    
    # Force kill if still running after timeout
    if kill -0 $CAM1_PID 2>/dev/null; then
        log "Camera 1 didn't stop gracefully after ${timeout}s, forcing shutdown"
        kill -KILL $CAM1_PID 2>/dev/null || true
    fi
    
    if kill -0 $CAM2_PID 2>/dev/null; then
        log "Camera 2 didn't stop gracefully after ${timeout}s, forcing shutdown"
        kill -KILL $CAM2_PID 2>/dev/null || true
    fi
    
    # Final wait
    wait $CAM1_PID 2>/dev/null || true
    wait $CAM2_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
    
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
