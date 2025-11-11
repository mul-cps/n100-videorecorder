#!/bin/bash
#
# Cleanup Old Recordings Script
#

set -e

# Load configuration
CONFIG_FILE="/etc/camera-recorder/camera-mapping.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
RECORDINGS_BASE="${RECORDINGS_BASE:-/storage/recordings}"
CLEANUP_DAYS="${CLEANUP_DAYS:-30}"
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-95}"
LOG_FILE="/var/log/camera-recorder/cleanup.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
    echo -e "${GREEN}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

warn() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') [WARN] $1"
    echo -e "${YELLOW}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
    echo -e "${RED}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

cleanup_old_files() {
    log "Cleaning up recordings older than $CLEANUP_DAYS days..."
    
    local files_removed=0
    local space_freed=0
    
    # Find and remove old files
    while IFS= read -r -d '' file; do
        local size=$(du -b "$file" | cut -f1)
        space_freed=$((space_freed + size))
        files_removed=$((files_removed + 1))
        
        log "Removing old file: $(basename "$file") ($(du -h "$file" | cut -f1))"
        rm -f "$file"
        
    done < <(find "$RECORDINGS_BASE" -name "*.mp4" -mtime +$CLEANUP_DAYS -print0 2>/dev/null)
    
    if [[ $files_removed -gt 0 ]]; then
        local space_mb=$((space_freed / 1024 / 1024))
        log "Cleanup complete: $files_removed files removed, ${space_mb}MB freed"
    else
        log "No old files found to clean up"
    fi
}

check_disk_usage() {
    local usage=$(df "$RECORDINGS_BASE" | tail -1 | awk '{print $5}' | sed 's/%//')
    local available=$(df -h "$RECORDINGS_BASE" | tail -1 | awk '{print $4}')
    
    log "Current disk usage: ${usage}% (${available} available)"
    
    if [[ $usage -gt $DISK_USAGE_THRESHOLD ]]; then
        warn "Disk usage critical (${usage}%) - performing emergency cleanup"
        emergency_cleanup
        return 1
    elif [[ $usage -gt 85 ]]; then
        warn "Disk usage high (${usage}%) - consider increasing cleanup frequency"
    fi
    
    return 0
}

emergency_cleanup() {
    warn "Emergency cleanup: removing oldest files to free space..."
    
    local target_usage=80
    local files_removed=0
    
    # Remove oldest files until we reach target usage
    while true; do
        local current_usage=$(df "$RECORDINGS_BASE" | tail -1 | awk '{print $5}' | sed 's/%//')
        
        if [[ $current_usage -le $target_usage ]]; then
            log "Emergency cleanup complete - disk usage now: ${current_usage}%"
            break
        fi
        
        # Find oldest file
        local oldest_file=$(find "$RECORDINGS_BASE" -name "*.mp4" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
        
        if [[ -z "$oldest_file" ]]; then
            error "No more files to remove, but disk still critical!"
            break
        fi
        
        local size=$(du -h "$oldest_file" | cut -f1)
        warn "Emergency removal: $(basename "$oldest_file") ($size)"
        rm -f "$oldest_file"
        files_removed=$((files_removed + 1))
        
        # Safety check - don't remove more than 100 files in one go
        if [[ $files_removed -gt 100 ]]; then
            error "Emergency cleanup removed $files_removed files but disk still critical"
            break
        fi
    done
    
    log "Emergency cleanup removed $files_removed files"
}

cleanup_empty_directories() {
    log "Removing empty directories..."
    
    # Remove empty date directories
    find "$RECORDINGS_BASE" -type d -empty -delete 2>/dev/null || true
    
    log "Empty directory cleanup complete"
}

generate_usage_report() {
    log "Generating storage usage report..."
    
    local report_file="/var/log/camera-recorder/storage-report.txt"
    
    {
        echo "Storage Usage Report - $(date)"
        echo "======================================"
        echo
        echo "Overall disk usage:"
        df -h "$RECORDINGS_BASE"
        echo
        echo "Directory sizes:"
        du -h "$RECORDINGS_BASE"/* 2>/dev/null | sort -hr || echo "No recordings found"
        echo
        echo "File count by camera:"
        for cam in cam1 cam2; do
            local cam_dir="$RECORDINGS_BASE/$cam"
            if [[ -d "$cam_dir" ]]; then
                local count=$(find "$cam_dir" -name "*.mp4" | wc -l)
                local size=$(du -sh "$cam_dir" 2>/dev/null | cut -f1)
                echo "  $cam: $count files, $size total"
            fi
        done
        echo
        echo "Recent recordings (last 24 hours):"
        find "$RECORDINGS_BASE" -name "*.mp4" -mtime -1 -ls 2>/dev/null | tail -10 || echo "No recent recordings"
        
    } > "$report_file"
    
    log "Usage report saved to: $report_file"
}

main() {
    log "Starting cleanup process..."
    
    # Check if recordings directory exists
    if [[ ! -d "$RECORDINGS_BASE" ]]; then
        error "Recordings directory not found: $RECORDINGS_BASE"
        exit 1
    fi
    
    # Check current disk usage
    check_disk_usage
    
    # Clean up old files
    cleanup_old_files
    
    # Clean up empty directories
    cleanup_empty_directories
    
    # Generate usage report
    generate_usage_report
    
    # Final disk usage check
    check_disk_usage
    
    log "Cleanup process complete"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
