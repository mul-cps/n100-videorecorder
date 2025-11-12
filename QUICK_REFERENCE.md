# Quick Reference Guide

## Current System Configuration

This is a quick reference for the **actual current state** of the n100-videorecorder system.

### Recording Settings (As Configured)

**Frame Rate:** 60 FPS (optimized for fast motion)  
**Resolution:** 2560x1440 (1440p)  
**Segment Length:** 1800 seconds (30-minute files)  
**Input Format:** H.264 from cameras  
**Output Mode:** Stream copy (no transcoding by default)  
**Encoding Codec:** `copy` (can be changed to `hevc_qsv` for H.265)  

### Camera Device Mapping

**Camera 1:** `/dev/video-usb1-video0` (or fallback: `/dev/video0`)  
**Camera 2:** `/dev/video-usb2-video3` (or fallback: `/dev/video2`)  

These use **persistent symlinks** created by udev rules based on USB bus position.

### File Locations

**Configuration:** `/etc/camera-recorder/camera-mapping.conf`  
**Service File:** `/etc/systemd/system/dual-camera-record.service`  
**Recording Script:** `/home/bjoern/git/n100-videorecorder/scripts/dual-camera-record.sh`  
**Recordings:** `/storage/recordings/cam1/` and `/storage/recordings/cam2/`  
**Logs:** `journalctl -u dual-camera-record` (systemd journal)  

### Service Management

```bash
# Start recording
sudo systemctl start dual-camera-record

# Stop recording
sudo systemctl stop dual-camera-record

# Restart service
sudo systemctl restart dual-camera-record

# Check status
sudo systemctl status dual-camera-record

# View logs in real-time
journalctl -u dual-camera-record -f

# View logs from last hour
journalctl -u dual-camera-record --since "1 hour ago"
```

### Common Commands

```bash
# Detect cameras
sudo ./scripts/detect-cameras.sh

# Check system status
sudo ./scripts/check-cameras.sh

# Test QSV support (if using hardware encoding)
sudo ./scripts/test-qsv.sh

# Test USB bandwidth
sudo ./scripts/usb-bandwidth-test.sh

# Run cleanup manually
sudo ./scripts/cleanup-recordings.sh

# Verify setup
sudo ./verify-setup.sh
```

### Directory Structure

```
/storage/recordings/
├── cam1/
│   ├── cam1_20251112_140000.mp4  (30-minute segment)
│   ├── cam1_20251112_143000.mp4
│   └── ...
└── cam2/
    ├── cam2_20251112_140000.mp4
    ├── cam2_20251112_143000.mp4
    └── ...
```

### Important Notes

1. **Username in Service:** The systemd service is configured for user `bjoern`. Change this in `/etc/systemd/system/dual-camera-record.service` if different.

2. **Stream Copy Mode:** Current default uses `ENCODING_CODEC="copy"` which provides:
   - Zero quality loss
   - Minimal CPU usage (2-5%)
   - Direct remuxing from camera H.264 to MP4
   - No transcoding overhead

3. **To Enable QSV Encoding:** Edit `/etc/camera-recorder/camera-mapping.conf`:
   ```bash
   ENCODING_CODEC="hevc_qsv"  # Instead of "copy"
   ```

4. **Segment Files:** With 30-minute segments at 1440p60:
   - File size: ~1.5-2.4 GB per 30-minute segment per camera
   - Storage per hour: ~3-5 GB per camera
   - Storage per day: ~72-120 GB per camera
   - With two cameras: ~150-240 GB per day

### Optimization Profiles

**Current Profile: CONVEYOR_BELT**
- Optimized for fast-moving objects
- High quality (CQP 23)
- 60 FPS for motion clarity
- VBR mode with 8-12 Mbps per camera
- 30-minute segments for manageable file sizes

**Alternative Profiles:**

To switch to a different profile, edit `/etc/camera-recorder/camera-mapping.conf`:

**HIGH_QUALITY:**
```bash
ENCODING_QUALITY="22"
ENCODING_PRESET="slow"
TARGET_BITRATE="12000"
SEGMENT_TIME="3600"  # 1-hour segments
```

**BALANCED:**
```bash
ENCODING_QUALITY="28"
ENCODING_PRESET="medium"
TARGET_BITRATE="5000"
SEGMENT_TIME="3600"
```

**LOW_STORAGE:**
```bash
ENCODING_QUALITY="32"
ENCODING_PRESET="fast"
TARGET_BITRATE="3000"
SEGMENT_TIME="3600"
```

### Troubleshooting Quick Checks

```bash
# 1. Are cameras connected?
ls -la /dev/video*

# 2. Is service running?
systemctl status dual-camera-record

# 3. Are recordings being created?
ls -lah /storage/recordings/cam1/ | tail -5

# 4. Check recent errors
journalctl -u dual-camera-record --since "10 minutes ago" | grep -i error

# 5. Check disk space
df -h /storage/recordings

# 6. Monitor CPU usage
top -p $(pgrep -d',' ffmpeg)
```

### Configuration Changes

After editing `/etc/camera-recorder/camera-mapping.conf`:

```bash
# Restart service to apply changes
sudo systemctl restart dual-camera-record

# Verify new settings are loaded
journalctl -u dual-camera-record --since "1 minute ago"
```

### Additional Documentation

- **README.md** - Project overview
- **DEPLOYMENT.md** - Detailed deployment guide
- **CONFIGURATION_UPDATE.md** - Recent configuration changes
- **CONVEYOR_BELT_OPTIMIZATION.md** - Motion capture optimizations
- **GRACEFUL_SHUTDOWN.md** - Service shutdown details
