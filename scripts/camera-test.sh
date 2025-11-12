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
# Try to find the correct FFmpeg binary
if [[ -x "/usr/lib/jellyfin-ffmpeg/ffmpeg" ]]; then
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"
elif [[ -x "/usr/local/bin/ffmpeg-qsv" ]]; then
    FFMPEG="/usr/local/bin/ffmpeg-qsv"
else
    FFMPEG="ffmpeg"
fi
TEST_DURATION=10
TEST_DIR="/tmp/camera-test"

cleanup() {
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

detect_best_format() {
    local device="$1"
    
    # Check for available formats in order of preference: H264, MJPEG, YUYV
    if v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -q "H264"; then
        echo "h264"
    elif v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -q "MJPEG"; then
        echo "mjpeg"
    elif v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -q "YUYV"; then
        echo "yuyv"
    else
        echo "unknown"
    fi
}

test_basic_capture() {
    local device="$1"
    local output="$2"
    
    log "Testing basic capture from $device..."
    
    local format=$(detect_best_format "$device")
    log "Using format: $format"
    
    if [[ "$format" == "h264" ]]; then
        # H264 input - re-encode to HEVC with QSV for space savings
        log "Command: $FFMPEG -f v4l2 -input_format h264 -video_size 1920x1080 -framerate 30 -i $device -c:v hevc_qsv -preset fast -global_quality 28 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size 1920x1080 \
            -framerate 30 \
            -i "$device" \
            -c:v hevc_qsv \
            -preset fast \
            -global_quality 28 \
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/basic_capture_test.log | tail -20
    elif [[ "$format" == "mjpeg" ]]; then
        log "Command: $FFMPEG -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i $device -c:v hevc_qsv -preset fast -global_quality 28 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
            -f v4l2 \
            -input_format mjpeg \
            -video_size 1920x1080 \
            -framerate 30 \
            -i "$device" \
            -c:v hevc_qsv \
            -preset fast \
            -global_quality 28 \
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/basic_capture_test.log | tail -20
    else
        log "Command: $FFMPEG -f v4l2 -video_size 1920x1080 -framerate 30 -i $device -c:v hevc_qsv -preset fast -global_quality 28 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
            -f v4l2 \
            -video_size 1920x1080 \
            -framerate 30 \
            -i "$device" \
            -c:v hevc_qsv \
            -preset fast \
            -global_quality 28 \
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/basic_capture_test.log | tail -20
    fi
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "Basic capture test PASSED - File size: $size"
        log "Full log saved to: /tmp/basic_capture_test.log"
        return 0
    else
        error "Basic capture test FAILED"
        error "Check log at: /tmp/basic_capture_test.log"
        cat /tmp/basic_capture_test.log
        return 1
    fi
}

test_qsv_encode() {
    local device="$1"
    local output="$2"
    
    log "Testing QSV H.265 encoding from $device..."
    
    # Set Intel driver environment
    export LIBVA_DRIVER_NAME=iHD
    
    local format=$(detect_best_format "$device")
    log "Using format: $format with QSV acceleration"
    
    if [[ "$format" == "h264" ]]; then
        # H264 input - decode with QSV and re-encode to HEVC
        log "Command: $FFMPEG -f v4l2 -input_format h264 -video_size 1920x1080 -framerate 30 -i $device -c:v hevc_qsv -preset medium -global_quality 28 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size 1920x1080 \
            -framerate 30 \
            -i "$device" \
            -c:v hevc_qsv \
            -preset medium \
            -global_quality 28 \
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/qsv_test.log | tail -20
    elif [[ "$format" == "mjpeg" ]]; then
        log "Command: $FFMPEG -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i $device -init_hw_device qsv=hw -filter_hw_device hw -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 -look_ahead 1 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
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
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/qsv_test.log | tail -20
    else
        log "Command: $FFMPEG -f v4l2 -video_size 1920x1080 -framerate 30 -i $device -init_hw_device qsv=hw -filter_hw_device hw -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 -look_ahead 1 -t $TEST_DURATION -y $output"
        timeout $((TEST_DURATION + 15)) "$FFMPEG" \
            -f v4l2 \
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
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/qsv_test.log | tail -20
    fi
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "QSV encoding test PASSED - File size: $size"
        
        # Check for QSV usage in log
        if grep -q "qsv" /tmp/qsv_test.log; then
            log "Hardware acceleration is working!"
        else
            warn "Hardware acceleration may not be active"
        fi
        log "Full log saved to: /tmp/qsv_test.log"
        return 0
    else
        error "QSV encoding test FAILED"
        error "Check log at: /tmp/qsv_test.log"
        cat /tmp/qsv_test.log
        return 1
    fi
}

test_4k_qsv() {
    local device="$1"
    local output="$2"
    
    log "Testing 4K QSV encoding from $device..."
    
    export LIBVA_DRIVER_NAME=iHD
    
    local format=$(detect_best_format "$device")
    log "Using format: $format for 4K capture with QSV"
    
    if [[ "$format" == "h264" ]]; then
        # H264 input at 4K - decode and re-encode to HEVC with QSV
        log "Command: $FFMPEG -f v4l2 -input_format h264 -video_size 3840x2160 -framerate 30 -i $device -c:v hevc_qsv -preset medium -global_quality 28 -t $TEST_DURATION -y $output"
        timeout $TEST_DURATION "$FFMPEG" \
            -f v4l2 \
            -input_format h264 \
            -video_size 3840x2160 \
            -framerate 30 \
            -i "$device" \
            -c:v hevc_qsv \
            -preset medium \
            -global_quality 28 \
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/4k_qsv_test.log | tail -20
    elif [[ "$format" == "mjpeg" ]]; then
        log "Command: $FFMPEG -f v4l2 -input_format mjpeg -video_size 3840x2160 -framerate 15 -i $device -init_hw_device qsv=hw -filter_hw_device hw -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 -look_ahead 1 -t $TEST_DURATION -y $output"
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
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/4k_qsv_test.log | tail -20
    else
        log "Command: $FFMPEG -f v4l2 -video_size 3840x2160 -framerate 15 -i $device -init_hw_device qsv=hw -filter_hw_device hw -vf hwupload=extra_hw_frames=64,format=qsv -c:v hevc_qsv -preset medium -global_quality 28 -look_ahead 1 -t $TEST_DURATION -y $output"
        timeout $TEST_DURATION "$FFMPEG" \
            -f v4l2 \
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
            -t $TEST_DURATION \
            -y "$output" 2>&1 | tee /tmp/4k_qsv_test.log | tail -20
    fi
    
    if [[ -f "$output" ]]; then
        local size=$(du -h "$output" | cut -f1)
        log "4K QSV encoding test PASSED - File size: $size"
        log "Full log saved to: /tmp/4k_qsv_test.log"
        return 0
    else
        error "4K QSV encoding test FAILED"
        error "Check log at: /tmp/4k_qsv_test.log"
        cat /tmp/4k_qsv_test.log
        return 1
    fi
}

benchmark_performance() {
    log "Running performance benchmark..."
    
    export LIBVA_DRIVER_NAME=iHD
    
    local start_time=$(date +%s)
    local cpu_start=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {print usage}')
    
    local cam1_format=$(detect_best_format "/dev/video0")
    local cam2_format=$(detect_best_format "/dev/video2")
    
    log "Camera 1 format: $cam1_format"
    log "Camera 2 format: $cam2_format"
    
    # Build FFmpeg command based on detected formats
    local cam1_input=""
    local cam2_input=""
    
    if [[ "$cam1_format" == "h264" ]]; then
        cam1_input="-f v4l2 -input_format h264 -video_size 1920x1080 -framerate 30 -i /dev/video0"
    elif [[ "$cam1_format" == "mjpeg" ]]; then
        cam1_input="-f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i /dev/video0"
    else
        cam1_input="-f v4l2 -video_size 1920x1080 -framerate 30 -i /dev/video0"
    fi
    
    if [[ "$cam2_format" == "h264" ]]; then
        cam2_input="-f v4l2 -input_format h264 -video_size 1920x1080 -framerate 30 -i /dev/video2"
    elif [[ "$cam2_format" == "mjpeg" ]]; then
        cam2_input="-f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i /dev/video2"
    else
        cam2_input="-f v4l2 -video_size 1920x1080 -framerate 30 -i /dev/video2"
    fi
    
    log "Starting dual camera benchmark (30 seconds)..."
    log "Command: $FFMPEG $cam1_input $cam2_input -map 0:v -c:v hevc_qsv ... -map 1:v -c:v hevc_qsv ..."
    
    # Record for 30 seconds from both cameras
    "$FFMPEG" \
        $cam1_input \
        $cam2_input \
        -map 0:v -c:v hevc_qsv -preset medium -global_quality 28 \
        -map 1:v -c:v hevc_qsv -preset medium -global_quality 28 \
        -t 30 \
        -y "$TEST_DIR/dual_test_cam1.mp4" \
        -y "$TEST_DIR/dual_test_cam2.mp4" \
        2>&1 | tee /tmp/benchmark.log | tail -30 &
    
    local ffmpeg_pid=$!
    
    # Monitor CPU usage during test
    log "Monitoring CPU usage..."
    local max_cpu=0
    for i in {1..30}; do
        sleep 1
        local current_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        if (( $(echo "$current_cpu > $max_cpu" | bc -l) )); then
            max_cpu=$current_cpu
        fi
        echo -n "."
    done
    echo
    
    wait $ffmpeg_pid
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Benchmark completed in ${duration}s"
    log "Peak CPU usage: ${max_cpu}%"
    log "Full log saved to: /tmp/benchmark.log"
    
    if [[ -f "$TEST_DIR/dual_test_cam1.mp4" && -f "$TEST_DIR/dual_test_cam2.mp4" ]]; then
        local size1=$(du -h "$TEST_DIR/dual_test_cam1.mp4" | cut -f1)
        local size2=$(du -h "$TEST_DIR/dual_test_cam2.mp4" | cut -f1)
        log "Dual camera test PASSED - Cam1: $size1, Cam2: $size2"
    else
        error "Dual camera test FAILED"
        error "Check log at: /tmp/benchmark.log"
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

    # Check device permissions so users don't have to run tests as root
    check_device_permissions() {
        local dev="/dev/video0"
        if [[ ! -e "$dev" ]]; then
            warn "Device $dev not present yet"
            return 0
        fi

        # If we can read and write the device as the current user, everything's fine
        if [[ -r "$dev" && -w "$dev" ]]; then
            return 0
        fi

        warn "Current user does not have read/write access to $dev."
        echo
        echo "To fix this so you don't need sudo, run one of the following (recommended):"
        echo "  1) Add your user to the 'video' group and re-login:" \
             "sudo usermod -a -G video \$USER && echo 'Then log out and log back in (or run: newgrp video)'"
        echo
        echo "  2) (Immediate, temporary) Fix current device nodes (will be reset on re-plug):"
        echo "sudo chown root:video /dev/video* && sudo chmod 660 /dev/video*"
        echo
        echo "If you installed this via the deploy script, the deploy process already adds the install user to the 'video' group — you must re-login for the change to take effect."
        echo
    }

    check_device_permissions
    
    check_system_resources
    
    # Test each camera
    for device in /dev/video0 /dev/video2; do
        if [[ -c "$device" ]]; then
            local cam_name=$(basename "$device")
            
            echo -e "${YELLOW}Testing $device...${NC}"
            
            test_basic_capture "$device" "$TEST_DIR/basic_$cam_name.mp4" || continue
            test_qsv_encode "$device" "$TEST_DIR/qsv_$cam_name.mp4" || continue
            
            # Only test 4K if device supports it
            local format=$(detect_best_format "$device")
            if v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null | grep -A10 "$format" | grep -q "3840x2160"; then
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
