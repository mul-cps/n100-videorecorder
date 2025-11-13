#!/bin/bash
#
# Automated HEVC Transcoding for Old Recordings
# Converts H.264 recordings older than N days to HEVC to save disk space
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

# Configuration
RECORDINGS_BASE="${RECORDINGS_BASE:-/storage/recordings}"
TRANSCODE_AGE_DAYS="${TRANSCODE_AGE_DAYS:-2}"  # Transcode files older than 2 days
ENCODING_QUALITY="${ENCODING_QUALITY:-23}"      # HEVC quality (18-28, lower=better)
ENCODING_PRESET="${ENCODING_PRESET:-medium}"    # fast, medium, slow
MAX_PARALLEL="${MAX_PARALLEL:-1}"               # Number of parallel transcodes
TEMP_DIR="${TEMP_DIR:-/tmp/transcode}"
LOG_DIR="/var/log/camera-recorder"

# FFmpeg binary
if [[ -x "/usr/lib/jellyfin-ffmpeg/ffmpeg" ]]; then
    FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"
else
    FFMPEG="ffmpeg"
fi

# Ensure iHD driver
export LIBVA_DRIVER_NAME=iHD

mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

LOGFILE="$LOG_DIR/transcode-$(date +%Y%m%d_%H%M%S).log"

echo "============================================" | tee -a "$LOGFILE"
echo "  Automated HEVC Transcoding" | tee -a "$LOGFILE"
echo "  $(date)" | tee -a "$LOGFILE"
echo "============================================" | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

log "Configuration:" | tee -a "$LOGFILE"
log "  Recordings: $RECORDINGS_BASE" | tee -a "$LOGFILE"
log "  Transcode files older than: $TRANSCODE_AGE_DAYS days" | tee -a "$LOGFILE"
log "  HEVC Quality: $ENCODING_QUALITY" | tee -a "$LOGFILE"
log "  Preset: $ENCODING_PRESET" | tee -a "$LOGFILE"
log "  Max Parallel: $MAX_PARALLEL" | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

# Function to check if file is already HEVC
is_hevc() {
    local file="$1"
    local codec=$("$FFMPEG" -i "$file" 2>&1 | grep "Video:" | grep -o "hevc\|h265")
    [[ -n "$codec" ]]
}

# Function to get file size in MB
get_size_mb() {
    local file="$1"
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    echo "scale=2; $size / 1024 / 1024" | bc
}

# Function to transcode a single file
transcode_file() {
    local input_file="$1"
    local filename=$(basename "$input_file")
    local dirname=$(dirname "$input_file")
    local temp_output="$TEMP_DIR/${filename%.mp4}_hevc.mp4"
    local final_output="${input_file%.mp4}_hevc.mp4"
    
    log "Transcoding: $filename" | tee -a "$LOGFILE"
    
    local original_size=$(get_size_mb "$input_file")
    log "  Original size: ${original_size} MB (H.264)" | tee -a "$LOGFILE"
    
    # Check if already transcoded
    if is_hevc "$input_file"; then
        info "  Already HEVC, skipping: $filename" | tee -a "$LOGFILE"
        return 0
    fi
    
    # Transcode to HEVC
    local start_time=$(date +%s)
    
    if "$FFMPEG" \
        -hwaccel qsv \
        -hwaccel_output_format qsv \
        -i "$input_file" \
        -c:v hevc_qsv \
        -preset "$ENCODING_PRESET" \
        -global_quality "$ENCODING_QUALITY" \
        -f mp4 \
        "$temp_output" \
        >> "$LOGFILE" 2>&1; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local new_size=$(get_size_mb "$temp_output")
        local savings=$(echo "scale=1; 100 * ($original_size - $new_size) / $original_size" | bc)
        
        log "  Transcoded size: ${new_size} MB (HEVC)" | tee -a "$LOGFILE"
        log "  Space saved: ${savings}%" | tee -a "$LOGFILE"
        log "  Time taken: ${duration}s" | tee -a "$LOGFILE"
        
        # Replace original with transcoded version
        mv "$temp_output" "$input_file"
        log "  ✓ Replaced original with HEVC version" | tee -a "$LOGFILE"
        
        # Track statistics
        echo "$original_size,$new_size,$savings,$duration" >> "$LOG_DIR/transcode-stats.csv"
        
        return 0
    else
        error "  ✗ Transcoding failed: $filename" | tee -a "$LOGFILE"
        rm -f "$temp_output"
        return 1
    fi
}

# Find files to transcode
log "Scanning for files older than $TRANSCODE_AGE_DAYS days..." | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

total_files=0
transcoded_files=0
failed_files=0
total_original_size=0
total_new_size=0

# Find all MP4 files older than specified days
for camera_dir in "$RECORDINGS_BASE"/cam*; do
    if [[ ! -d "$camera_dir" ]]; then
        continue
    fi
    
    camera_name=$(basename "$camera_dir")
    log "Processing $camera_name..." | tee -a "$LOGFILE"
    
    # Find files older than N days
    while IFS= read -r -d '' file; do
        ((total_files++))
        
        # Check if file is currently being written to
        if lsof "$file" >/dev/null 2>&1; then
            warn "  Skipping (in use): $(basename $file)" | tee -a "$LOGFILE"
            continue
        fi
        
        # Transcode the file
        if transcode_file "$file"; then
            ((transcoded_files++))
        else
            ((failed_files++))
        fi
        
        echo | tee -a "$LOGFILE"
        
    done < <(find "$camera_dir" -name "*.mp4" -type f -mtime +${TRANSCODE_AGE_DAYS} -print0)
    
done

# Summary
echo "============================================" | tee -a "$LOGFILE"
echo "  Transcoding Complete" | tee -a "$LOGFILE"
echo "============================================" | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"
log "Summary:" | tee -a "$LOGFILE"
log "  Total files found: $total_files" | tee -a "$LOGFILE"
log "  Successfully transcoded: $transcoded_files" | tee -a "$LOGFILE"
log "  Failed: $failed_files" | tee -a "$LOGFILE"

# Calculate total savings from stats file
if [[ -f "$LOG_DIR/transcode-stats.csv" ]]; then
    total_savings=$(awk -F',' '{saved+=$1-$2} END {print saved}' "$LOG_DIR/transcode-stats.csv")
    log "  Total space saved: ${total_savings} MB" | tee -a "$LOGFILE"
fi

echo | tee -a "$LOGFILE"
log "Log file: $LOGFILE" | tee -a "$LOGFILE"

# Cleanup temp directory
rm -rf "$TEMP_DIR"

# Check disk space after transcoding
df -h "$RECORDINGS_BASE" | tee -a "$LOGFILE"

exit 0
