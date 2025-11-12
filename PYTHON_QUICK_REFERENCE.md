# Python Version - Quick Reference

Quick command reference for the Python implementation of N100 Video Recorder.

## 🚀 Common Commands

### Daily Operations

```bash
# Check recording status
sudo systemctl status camera-recorder

# View live logs
journalctl -u camera-recorder -f

# Check statistics
camera-recorder --stats

# View disk usage
df -h /storage
```

### Service Management

```bash
# Start recording
sudo systemctl start camera-recorder

# Stop recording
sudo systemctl stop camera-recorder

# Restart recording
sudo systemctl restart camera-recorder

# Enable on boot
sudo systemctl enable camera-recorder

# Disable on boot
sudo systemctl disable camera-recorder

# Check if enabled
systemctl is-enabled camera-recorder
```

### Camera Management

```bash
# Detect all cameras
camera-recorder --detect

# Validate configuration
camera-recorder --validate

# Test configuration (dry-run)
camera-recorder --config /etc/camera-recorder/config.yaml --validate
```

### Storage Management

```bash
# View statistics
camera-recorder --stats

# Run cleanup (preview)
camera-recorder --cleanup --dry-run

# Run cleanup (actual)
camera-recorder --cleanup

# Check disk space
df -h /storage
du -sh /storage/recordings/*
```

## 📁 Important Files

### Configuration
```
/etc/camera-recorder/config.yaml          # Main configuration
/etc/camera-recorder/camera-mapping.conf  # Legacy bash config (backup)
```

### Service
```
/etc/systemd/system/camera-recorder.service  # SystemD service file
```

### Logs
```
/var/log/camera-recorder/camera-recorder.log  # Main application log
/var/log/camera-recorder/cam1.log             # Camera 1 FFmpeg log
/var/log/camera-recorder/cam2.log             # Camera 2 FFmpeg log
```

### Recordings
```
/storage/recordings/cam1/  # Camera 1 recordings
/storage/recordings/cam2/  # Camera 2 recordings
```

## 🔍 Monitoring

### Real-time Monitoring

```bash
# Live service logs
journalctl -u camera-recorder -f

# Live camera logs
tail -f /var/log/camera-recorder/cam1.log
tail -f /var/log/camera-recorder/cam2.log

# Watch new files being created
watch -n 5 'ls -lh /storage/recordings/cam1/ | tail -5'

# Monitor disk space
watch -n 30 'df -h /storage'
```

### Historical Logs

```bash
# Last 100 lines
journalctl -u camera-recorder -n 100

# Last hour
journalctl -u camera-recorder --since "1 hour ago"

# Last 24 hours
journalctl -u camera-recorder --since "24 hours ago"

# Specific date
journalctl -u camera-recorder --since "2024-11-12" --until "2024-11-13"

# With timestamps
journalctl -u camera-recorder -o short-precise
```

## 📊 Statistics & Analysis

### Quick Stats

```bash
# Full statistics
camera-recorder --stats

# Recordings count
find /storage/recordings -name "*.mp4" | wc -l

# Total storage used
du -sh /storage/recordings

# Per-camera storage
du -sh /storage/recordings/cam1
du -sh /storage/recordings/cam2

# Latest recordings
ls -lht /storage/recordings/cam1/ | head -5
ls -lht /storage/recordings/cam2/ | head -5

# Oldest recordings
ls -lt /storage/recordings/cam1/ | tail -5
ls -lt /storage/recordings/cam2/ | tail -5
```

### Advanced Analysis

```bash
# Files by date
find /storage/recordings -name "*.mp4" -printf "%TY-%Tm-%Td %p\n" | sort

# Files older than 30 days
find /storage/recordings -name "*.mp4" -mtime +30

# Average file size
du -b /storage/recordings/cam1/*.mp4 | awk '{total+=$1; count++} END {print total/count/1024/1024 " MB"}'

# Files created today
find /storage/recordings -name "*.mp4" -mtime 0

# Disk usage trend
df -h /storage | tail -1 | awk '{print $5}'
```

## 🔧 Configuration

### View Current Configuration

```bash
# Display YAML config
cat /etc/camera-recorder/config.yaml

# Validate YAML syntax
python3 -c "import yaml; print(yaml.safe_load(open('/etc/camera-recorder/config.yaml')))"

# Validate with application
camera-recorder --validate
```

### Edit Configuration

```bash
# Edit config
sudo nano /etc/camera-recorder/config.yaml

# Validate changes
camera-recorder --validate

# Apply changes (restart service)
sudo systemctl restart camera-recorder

# Verify
journalctl -u camera-recorder -f
```

### Common Config Changes

```yaml
# Change segment duration to 60 minutes
recording:
  segment_time: 3600  # 60 minutes in seconds

# Change cleanup retention to 60 days
storage:
  cleanup_days: 60

# Disable a camera
cameras:
  cam2:
    enabled: false

# Change encoding to HEVC QSV
encoding:
  codec: "hevc_qsv"
  preset: "fast"
  quality: 23
```

## 🐛 Troubleshooting

### Service Issues

```bash
# Service won't start
sudo systemctl status camera-recorder  # Check status
journalctl -u camera-recorder -n 50    # Check recent logs

# Service keeps restarting
journalctl -u camera-recorder | grep -i error

# Check if Python package is installed
pip3 show camera-recorder
camera-recorder --version
```

### Camera Issues

```bash
# Cameras not detected
camera-recorder --detect
ls -la /dev/video*

# Re-trigger udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Check camera permissions
ls -la /dev/video-usb*
groups $USER  # Should include 'video'

# Test camera directly
ffmpeg -f v4l2 -list_formats all -i /dev/video0
```

### Storage Issues

```bash
# Disk full
df -h /storage
camera-recorder --stats
camera-recorder --cleanup  # Run cleanup

# Cleanup not working
camera-recorder --cleanup --dry-run  # Preview
journalctl -u camera-recorder | grep cleanup

# Permissions
ls -la /storage/recordings
sudo chown -R $USER:$USER /storage/recordings
```

### Recording Issues

```bash
# No new files being created
ls -lht /storage/recordings/cam1/ | head
systemctl status camera-recorder
journalctl -u camera-recorder | grep -i error

# Files too small/large
camera-recorder --stats
ls -lh /storage/recordings/cam1/ | tail -10

# Corruption or playback issues
ffmpeg -v error -i /storage/recordings/cam1/latest.mp4 -f null -
```

## 🔄 Maintenance Tasks

### Daily

```bash
# Check service status
sudo systemctl status camera-recorder

# Quick disk check
df -h /storage
```

### Weekly

```bash
# Review statistics
camera-recorder --stats

# Check logs for errors
journalctl -u camera-recorder --since "7 days ago" | grep -i error

# Verify recordings playback
ffplay /storage/recordings/cam1/$(ls -t /storage/recordings/cam1/ | head -1)
```

### Monthly

```bash
# Review storage trends
camera-recorder --stats

# Test cleanup
camera-recorder --cleanup --dry-run

# Check for updates
cd /home/bjoern/git/n100-videorecorder
git pull

# Restart service (apply updates)
sudo systemctl restart camera-recorder
```

## 📝 One-Liners

```bash
# Total recordings today
find /storage/recordings -name "*.mp4" -mtime 0 | wc -l

# Storage per day (last 7 days)
for i in {0..7}; do echo "$(date -d "$i days ago" +%Y-%m-%d): $(find /storage/recordings -name "*.mp4" -mtime $i -printf "%s\n" | awk '{s+=$1} END {print s/1024/1024/1024 " GB"}')"; done

# Check if recording right now
ps aux | grep camera-recorder | grep -v grep

# FFmpeg processes
ps aux | grep ffmpeg | grep -v grep

# Latest recording timestamp
ls -lt /storage/recordings/cam1/*.mp4 | head -1 | awk '{print $6, $7, $8}'

# Count files per camera
echo "cam1: $(ls /storage/recordings/cam1/*.mp4 2>/dev/null | wc -l) files"
echo "cam2: $(ls /storage/recordings/cam2/*.mp4 2>/dev/null | wc -l) files"

# Restart if not running
systemctl is-active --quiet camera-recorder || sudo systemctl start camera-recorder

# Emergency cleanup (remove files older than 14 days)
find /storage/recordings -name "*.mp4" -mtime +14 -delete

# Verify all MP4 files integrity
find /storage/recordings -name "*.mp4" -exec ffmpeg -v error -i {} -f null - \;
```

## 🎯 Common Scenarios

### "Disk is full"

```bash
# Check usage
df -h /storage

# See what's using space
du -sh /storage/recordings/*

# Run cleanup
camera-recorder --cleanup

# If still critical, emergency cleanup
find /storage/recordings -name "*.mp4" -mtime +7 -delete
```

### "Recording stopped unexpectedly"

```bash
# Check service status
sudo systemctl status camera-recorder

# Review recent logs
journalctl -u camera-recorder -n 100

# Restart service
sudo systemctl restart camera-recorder

# Monitor
journalctl -u camera-recorder -f
```

### "Camera not detected"

```bash
# Check physical connection
lsusb | grep -i camera

# Check device files
ls -la /dev/video*

# Re-detect
camera-recorder --detect

# Reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger

# Restart service
sudo systemctl restart camera-recorder
```

### "Need to change resolution/framerate"

```bash
# Edit config
sudo nano /etc/camera-recorder/config.yaml

# Example: Change to 1080p@30fps
cameras:
  cam1:
    resolution: "1920x1080"
    framerate: 30

# Validate
camera-recorder --validate

# Apply
sudo systemctl restart camera-recorder
```

### "Export recordings for specific date"

```bash
# Find recordings for date
find /storage/recordings -name "*20241112*"

# Copy to USB drive
rsync -av --progress /storage/recordings/cam1/cam1_20241112* /media/usb/

# Create compressed archive
tar -czf recordings_20241112.tar.gz /storage/recordings/*/cam*_20241112*
```

## 🔐 Security Notes

```bash
# Ensure only authorized users can access
sudo chown -R bjoern:bjoern /etc/camera-recorder
sudo chmod 600 /etc/camera-recorder/config.yaml

# Restrict log access
sudo chown -R bjoern:bjoern /var/log/camera-recorder
sudo chmod 700 /var/log/camera-recorder

# Service runs as unprivileged user
grep User /etc/systemd/system/camera-recorder.service
```

## 📞 Quick Support Checklist

When reporting issues, collect:

```bash
# 1. Service status
sudo systemctl status camera-recorder > /tmp/status.txt

# 2. Recent logs
journalctl -u camera-recorder -n 200 > /tmp/logs.txt

# 3. Configuration
cat /etc/camera-recorder/config.yaml > /tmp/config.txt

# 4. Camera detection
camera-recorder --detect > /tmp/detect.txt

# 5. Statistics
camera-recorder --stats > /tmp/stats.txt

# 6. System info
uname -a > /tmp/system.txt
df -h >> /tmp/system.txt
free -h >> /tmp/system.txt

# Create archive
tar -czf camera-recorder-debug.tar.gz /tmp/{status,logs,config,detect,stats,system}.txt
```

---

**Tip**: Bookmark this page for quick reference during daily operations!
