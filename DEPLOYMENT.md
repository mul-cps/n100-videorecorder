# N100 Video Recorder - Deployment Guide

This guide covers the complete setup and deployment process for the N100 Video Recorder system.

## Prerequisites

- Intel N100 mini PC
- Ubuntu 22.04 LTS or newer (fresh installation recommended)
- Two USB 4K cameras
- At least 1TB storage (USB 3.0 external drive recommended)
- WiFi connectivity
- SSH access (for remote management)

## Quick Deployment

### 1. Initial System Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Clone repository
git clone <your-repo-url> /home/$(whoami)/n100-videorecorder
cd /home/$(whoami)/n100-videorecorder

# Run automated deployment (installs dependencies, drivers, etc.)
sudo ./deploy.sh
```

### 2. Configure Network

```bash
# Set up WiFi (if needed)
sudo ./scripts/setup-wifi.sh

# Edit WiFi credentials
sudo nano /etc/netplan/50-wifi.yaml

# Apply network configuration
sudo netplan apply
```

### 3. Detect and Configure Cameras

```bash
# Detect available cameras and their capabilities
sudo ./scripts/detect-cameras.sh

# Configure camera mapping based on detection
sudo nano /etc/camera-recorder/camera-mapping.conf
```

**Important**: Update the camera device paths to match your system:
- Check output from `detect-cameras.sh`
- Use persistent symlinks like `/dev/video-usb1-video0` (preferred)
- Or use direct devices like `/dev/video0`, `/dev/video2`

### 4. Update and Install Service

```bash
# Edit service file to use YOUR username (currently set to 'bjoern')
sudo nano systemd/dual-camera-record.service
# Change: User=bjoern to User=yourusername

# Copy service file to systemd
sudo cp systemd/dual-camera-record.service /etc/systemd/system/

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable dual-camera-record
```

### 5. Verify and Start

```bash
# Run verification tests
sudo ./verify-setup.sh

# Start recording service
sudo systemctl start dual-camera-record

# Check status
sudo systemctl status dual-camera-record

# Monitor logs in real-time
journalctl -u dual-camera-record -f
```

## Manual Configuration

### Camera Device Mapping

The system uses **persistent symlinks** created by udev rules to ensure cameras maintain consistent device assignments.

1. **Check current camera devices:**
   ```bash
   ls -la /dev/video*
   # Look for symlinks like: /dev/video-usb1-video0 -> video0
   ```

2. **Detect cameras and their USB positions:**
   ```bash
   sudo ./scripts/detect-cameras.sh
   ```

3. **Update configuration:**
   ```bash
   sudo nano /etc/camera-recorder/camera-mapping.conf
   ```

4. **Example configurations:**
   
   **Using persistent symlinks (recommended):**
   ```bash
   CAMERA1_DEVICE="/dev/video-usb1-video0"
   CAMERA2_DEVICE="/dev/video-usb2-video3"
   ```
   
   **Using direct device nodes (less reliable):**
   ```bash
   CAMERA1_DEVICE="/dev/video0"
   CAMERA2_DEVICE="/dev/video2"
   ```

5. **Custom udev rules (advanced):**
   
   Get camera vendor/product IDs:
   ```bash
   lsusb
   udevadm info -a -p $(udevadm info -q path -n /dev/video0)
   ```
   
   Edit udev rules:
   ```bash
   sudo nano /etc/udev/rules.d/99-camera-mapping.rules
   ```
   
   Add camera-specific rules:
   ```
   SUBSYSTEM=="video4linux", ATTRS{idVendor}=="XXXX", ATTRS{idProduct}=="YYYY", SYMLINK+="camera-primary"
   ```

### Storage Configuration

The system stores recordings in `/storage/recordings/` by default. To use a different location:

1. **Edit configuration:**
   ```bash
   sudo nano /etc/camera-recorder/camera-mapping.conf
   ```

2. **Update RECORDINGS_BASE path:**
   ```bash
   RECORDINGS_BASE="/path/to/your/storage"
   ```

3. **Ensure permissions:**
   ```bash
   sudo chown -R $USER:$USER /path/to/your/storage
   chmod -R 755 /path/to/your/storage
   ```

### Quality Settings

Adjust encoding quality in `/etc/camera-recorder/camera-mapping.conf`:

**Current Settings (Optimized for Fast Motion/Conveyor Belt):**
```bash
ENCODING_PRESET="fast"          # Fast preset for better motion handling
ENCODING_QUALITY="23"           # High quality (lower = better, 18-32 range)
BITRATE_MODE="VBR"              # Variable bitrate for consistent quality
TARGET_BITRATE="8000"           # 8 Mbps target
MAX_BITRATE="12000"             # 12 Mbps maximum
GOP_SIZE="60"                   # 1 keyframe per second at 60fps
```

**For Different Use Cases:**

- **Stream Copy (No Transcoding - Current Default):**
  ```bash
  ENCODING_CODEC="copy"
  # Fastest, zero quality loss, minimal CPU usage
  ```

- **Higher quality (larger files):**
  ```bash
  ENCODING_CODEC="hevc_qsv"
  ENCODING_QUALITY="22"
  TARGET_BITRATE="10000"
  ```

- **Balanced (medium quality, smaller files):**
  ```bash
  ENCODING_QUALITY="28"
  TARGET_BITRATE="5000"
  ```

- **Maximum compression (smaller files, lower quality):**
  ```bash
  ENCODING_QUALITY="32"
  ENCODING_PRESET="fast"
  TARGET_BITRATE="3000"
  ```

### Resolution Settings

Current default is 1440p (2560x1440) at 60fps. To change:

```bash
sudo nano /etc/camera-recorder/camera-mapping.conf
```

**Common resolutions:**
```bash
# 4K UHD
CAMERA1_RESOLUTION="3840x2160"

# 1440p (current default)
CAMERA1_RESOLUTION="2560x1440"

# 1080p Full HD
CAMERA1_RESOLUTION="1920x1080"

# 720p HD
CAMERA1_RESOLUTION="1280x720"
```

**Frame rate options:**
```bash
# High motion (current default)
CAMERA1_FRAMERATE="60"

# Standard
CAMERA1_FRAMERATE="30"

# Low bandwidth
CAMERA1_FRAMERATE="15"
```

**Important**: Verify your camera supports the resolution and frame rate:
```bash
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

## Remote Management

### SSH Access

1. **Enable SSH:**
   ```bash
   sudo systemctl enable ssh
   sudo systemctl start ssh
   ```

2. **Set up key-based authentication:**
   ```bash
   # On your local machine
   ssh-copy-id user@n100-ip-address
   ```

### Tailscale VPN (Recommended)

1. **Install Tailscale:**
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

2. **Access via Tailscale IP:**
   ```bash
   ssh user@tailscale-ip
   ```

### Web Interface (Optional)

To enable a simple web interface for log viewing:

1. **Install nginx:**
   ```bash
   sudo apt install nginx
   ```

2. **Configure web server:**
   ```bash
   sudo cp docs/nginx-config.conf /etc/nginx/sites-available/camera-logs
   sudo ln -s /etc/nginx/sites-available/camera-logs /etc/nginx/sites-enabled/
   sudo systemctl restart nginx
   ```

## Monitoring and Maintenance

### Check System Status

```bash
# Overall system status
sudo ./scripts/check-cameras.sh

# View recording logs (recommended)
journalctl -u dual-camera-record -f

# View camera-specific logs (if they exist)
tail -f /var/log/camera-recorder/camera1-qsv.log
tail -f /var/log/camera-recorder/camera2-qsv.log
tail -f /var/log/camera-recorder/dual-camera.log

# Check disk usage
df -h /storage/recordings

# View recent recordings
ls -lah /storage/recordings/cam1/ | tail -10
ls -lah /storage/recordings/cam2/ | tail -10

# Count recordings by camera
find /storage/recordings/cam1 -name "*.mp4" | wc -l
find /storage/recordings/cam2 -name "*.mp4" | wc -l
```

### Performance Monitoring

```bash
# Monitor CPU usage
htop

# Monitor GPU usage
intel_gpu_top

# Check temperature
sensors
```

### Log Files

- **Service logs:** `journalctl -u dual-camera-record`
- **Camera logs:** `/var/log/camera-recorder/`
- **System logs:** `/var/log/syslog`

## Troubleshooting

### Common Issues

**1. Cameras not detected:**
```bash
# Check USB devices
lsusb
dmesg | grep uvc

# List all video devices
ls -la /dev/video*

# Test camera detection
sudo ./scripts/detect-cameras.sh

# Check if udev symlinks exist
ls -la /dev/video-usb*
```

**2. Recording service fails to start:**
```bash
# Check service status and errors
systemctl status dual-camera-record
journalctl -u dual-camera-record --since "10 minutes ago" --no-pager

# Verify camera devices in config match actual devices
cat /etc/camera-recorder/camera-mapping.conf | grep CAMERA._DEVICE
ls -la /dev/video*

# Test manual recording
sudo /home/$(whoami)/git/n100-videorecorder/scripts/dual-camera-record.sh

# Check camera permissions
groups | grep -E "video|render"
```

**3. QSV not working (if using hardware encoding):**
```bash
# Check Intel GPU
lspci | grep -i intel
vainfo

# Test QSV encoding
sudo ./scripts/test-qsv.sh

# Verify FFmpeg has QSV support
/usr/lib/jellyfin-ffmpeg/ffmpeg -encoders 2>&1 | grep qsv
```

**4. Camera streams show errors:**
```bash
# Test camera directly with FFmpeg
ffmpeg -f v4l2 -input_format h264 -video_size 1920x1080 -i /dev/video0 -t 5 test.mp4

# Check USB bandwidth (if multiple cameras on same bus)
sudo ./scripts/usb-bandwidth-test.sh

# Verify camera format support
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

**5. High CPU usage:**
```bash
# Check if stream copy mode is enabled (should be for H.264 cameras)
cat /etc/camera-recorder/camera-mapping.conf | grep ENCODING_CODEC

# If using QSV encoding, verify hardware acceleration is active
journalctl -u dual-camera-record | grep -i "qsv\|hwaccel"

# Monitor FFmpeg processes
top -p $(pgrep -d',' ffmpeg)
```

**4. Disk space issues:**
```bash
# Check disk usage
df -h

# Run manual cleanup
sudo /usr/local/bin/cleanup-recordings.sh

# Adjust retention settings
sudo nano /etc/camera-recorder/camera-mapping.conf
```

### Recovery Procedures

**Service won't start:**
```bash
# Reset service completely
sudo systemctl stop dual-camera-record
sudo systemctl disable dual-camera-record

# Verify service file is correct
sudo nano /etc/systemd/system/dual-camera-record.service
# Check: User matches your username, ExecStart path is correct

# Reload and re-enable
sudo systemctl daemon-reload
sudo systemctl enable dual-camera-record
sudo systemctl start dual-camera-record

# Monitor startup
journalctl -u dual-camera-record -f
```

**Corrupted recordings:**
```bash
# Check file integrity
find /storage/recordings -name "*.mp4" -exec ffprobe {} \; 2>&1 | grep -i error

# Remove small/corrupted files (less than 100KB)
find /storage/recordings -name "*.mp4" -size -100k -delete

# Verify disk is not full
df -h /storage/recordings
```

**Permission issues:**
```bash
# Fix ownership of recordings directory
sudo chown -R $USER:$USER /storage/recordings

# Ensure user is in video/render groups
sudo usermod -a -G video,render $USER
# Log out and back in for group changes to take effect

# Fix script permissions
chmod +x /home/$(whoami)/git/n100-videorecorder/scripts/*.sh
```

## Performance Optimization

### For Maximum Performance

1. **Use fastest storage available:**
   - NVMe SSD > SATA SSD > USB 3.0 HDD

2. **Optimize encoding settings:**
   ```bash
   ENCODING_PRESET="fast"      # Faster encoding
   ENCODING_QUALITY="30"       # Smaller files
   SEGMENT_TIME="1800"         # 30-minute segments
   ```

3. **Monitor system resources:**
   ```bash
   # Watch CPU usage during recording
   watch -n 1 'grep "cpu " /proc/stat | awk "{usage=(\$2+\$4)*100/(\$2+\$3+\$4+\$5)} END {print usage \"%\"}"'
   ```

### For Maximum Quality

1. **Use higher quality settings:**
   ```bash
   ENCODING_PRESET="slow"      # Better quality
   ENCODING_QUALITY="22"       # Larger files, better quality
   ```

2. **Ensure adequate cooling:**
   - Monitor CPU temperature
   - Ensure case ventilation

## Backup and Restore

### Backup Configuration

```bash
# Create backup of configuration
sudo tar -czf camera-config-backup.tar.gz \
    /etc/camera-recorder/ \
    /etc/systemd/system/dual-camera-record.service \
    /etc/udev/rules.d/99-camera-mapping.rules
```

### Restore Configuration

```bash
# Restore configuration
sudo tar -xzf camera-config-backup.tar.gz -C /

# Reload services
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl restart dual-camera-record
```

## Scaling and Customization

### Adding More Cameras

1. **Modify recording script:**
   ```bash
   sudo nano /usr/local/bin/dual-camera-record.sh
   ```

2. **Add third camera:**
   ```bash
   # Add similar ffmpeg command for /dev/video4
   ```

3. **Update configuration:**
   ```bash
   sudo nano /etc/camera-recorder/camera-mapping.conf
   ```

### Custom Post-Processing

Create custom scripts in `/usr/local/bin/` for:
- Automatic video compression
- Cloud backup uploads
- Motion detection
- Thumbnail generation

## Support and Updates

### Getting Help

1. **Check logs first:**
   ```bash
   sudo ./scripts/check-cameras.sh
   journalctl -u dual-camera-record --since today
   ```

2. **Test components individually:**
   ```bash
   sudo ./scripts/test-qsv.sh
   sudo ./scripts/camera-test.sh
   ```

3. **Gather system information:**
   ```bash
   # System info
   lscpu
   lsusb
   lspci | grep -i intel
   df -h
   free -h
   ```

### Updates

To update the recording system:

```bash
cd /home/$(whoami)/n100-videorecorder
git pull
sudo ./deploy.sh --update-only
```

Remember to back up your configuration before updating!
