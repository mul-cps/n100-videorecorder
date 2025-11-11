#!/bin/bash
#
# Camera Test Script - Test camera capture and QSV encoding
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"
TEST_DURATION=10
TEST_DIR="/tmp/camera-test"

cleanup() {
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

test_basic_capture() {
    local device="$1"
    local output="$2"
    
    log "Testing basic capture from $device..."
    
    timeout $TEST_DURATION "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i "$device" \
        -c:v libx264 \
        -preset fast \
        -y "$output" &>/dev/null
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "Basic capture test PASSED - File size: $size"
        return 0
    else
        error "Basic capture test FAILED"
        return 1
    fi
}

test_qsv_encode() {
    local device="$1"
    local output="$2"
    
    log "Testing QSV H.265 encoding from $device..."
    
    # Set Intel driver environment
    export LIBVA_DRIVER_NAME=iHD
    
    timeout $TEST_DURATION "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i "$device" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset medium \
        -global_quality 28 \
        -look_ahead 1 \
        -y "$output" 2>/tmp/qsv_test.log
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "QSV encoding test PASSED - File size: $size"
        
        # Check for QSV usage in log
        if grep -q "hwaccel" /tmp/qsv_test.log; then
            log "Hardware acceleration is working!"
        else
            warn "Hardware acceleration may not be active"
        fi
        return 0
    else
        error "QSV encoding test FAILED"
        cat /tmp/qsv_test.log
        return 1
    fi
}

test_4k_qsv() {
    local device="$1"
    local output="$2"
    
    log "Testing 4K QSV encoding from $device..."
    
    export LIBVA_DRIVER_NAME=iHD
    
    timeout $TEST_DURATION "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 3840x2160 \
        -framerate 15 \
        -i "$device" \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -vf hwupload=extra_hw_frames=64,format=qsv \
        -c:v hevc_qsv \
        -preset medium \
        -global_quality 28 \
        -look_ahead 1 \
        -y "$output" 2>/tmp/4k_qsv_test.log
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "4K QSV encoding test PASSED - File size: $size"
        return 0
    else
        error "4K QSV encoding test FAILED"
        cat /tmp/4k_qsv_test.log
        return 1
    fi
}

benchmark_performance() {
    log "Running performance benchmark..."
    
    export LIBVA_DRIVER_NAME=iHD
    
    local start_time=$(date +%s)
    local cpu_start=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {print usage}')
    
    # Record for 30 seconds from both cameras
    "$FFMPEG" \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i /dev/video0 \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i /dev/video2 \
        -init_hw_device qsv=hw \
        -filter_hw_device hw \
        -map 0:v -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 \
        -map 1:v -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 \
        -t 30 \
        -y "$TEST_DIR/dual_test_cam1.mp4" \
        -y "$TEST_DIR/dual_test_cam2.mp4" \
        2>/tmp/benchmark.log &
    
    local ffmpeg_pid=$!
    
    # Monitor CPU usage during test
    local max_cpu=0
    for i in {1..30}; do
        sleep 1
        local current_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        if (( $(echo "$current_cpu > $max_cpu" | bc -l) )); then
            max_cpu=$current_cpu
        fi
    done
    
    wait $ffmpeg_pid
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Benchmark completed in ${duration}s"
    log "Peak CPU usage: ${max_cpu}%"
    
    if [[ -f "$TEST_DIR/dual_test_cam1.mp4" && -f "$TEST_DIR/dual_test_cam2.mp4" ]]; then
        local size1=$(du -h "$TEST_DIR/dual_test_cam1.mp4" | cut -f1)
        local size2=$(du -h "$TEST_DIR/dual_test_cam2.mp4" | cut -f1)
        log "Dual camera test PASSED - Cam1: $size1, Cam2: $size2"
    else
        error "Dual camera test FAILED"
    fi
}

check_system_resources() {
    log "Checking system resources..."
    
    echo "CPU Info:"
    lscpu | grep -E "(Model name|CPU\(s\)|Thread|Core)"
    echo
    
    echo "Memory:"
    free -h
    echo
    
    echo "Storage:"
    df -h /storage 2>/dev/null || df -h /
    echo
    
    echo "GPU Info:"
    lspci | grep -i "VGA\|3D" || echo "No GPU info available"
    echo
}

main() {
    echo -e "${GREEN}===========================${NC}"
    echo -e "${GREEN}    Camera Test Suite${NC}"
    echo -e "${GREEN}===========================${NC}"
    echo
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    # Check prerequisites
    if [[ ! -x "$FFMPEG" ]]; then
        error "FFmpeg not found at $FFMPEG"
        exit 1
    fi
    
    check_system_resources
    
    # Test each camera
    for device in /dev/video0 /dev/video2; do
        if [[ -c "$device" ]]; then
            local cam_name=$(basename "$device")
            
            echo -e "${YELLOW}Testing $device...${NC}"
            
            test_basic_capture "$device" "$TEST_DIR/basic_$cam_name.mp4" || continue
            test_qsv_encode "$device" "$TEST_DIR/qsv_$cam_name.mp4" || continue
            
            # Only test 4K if device supports it
            if v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -A5 "MJPEG" | grep -q "3840x2160"; then
                test_4k_qsv "$device" "$TEST_DIR/4k_qsv_$cam_name.mp4"
            fi
            
            echo
        else
            warn "Device $device not found"
        fi
    done
    
    # Test dual camera if both devices exist
    if [[ -c "/dev/video0" && -c "/dev/video2" ]]; then
        echo -e "${YELLOW}Testing dual camera recording...${NC}"
        benchmark_performance
    fi
    
    echo
    echo -e "${GREEN}Test Results Summary:${NC}"
    ls -lh "$TEST_DIR"/*.mp4 2>/dev/null | awk '{print "  " $9 ": " $5}' || echo "  No test files created"
    echo
    
    log "Camera testing complete!"
    echo "Test files available in: $TEST_DIR"
}

main "$@"
