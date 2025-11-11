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

# Run automated deployment
sudo ./deploy.sh
```

### 2. Configure Network

```bash
# Set up WiFi
sudo ./scripts/setup-wifi.sh

# Edit WiFi credentials
sudo nano /etc/netplan/50-wifi.yaml

# Apply network configuration
sudo netplan apply
```

### 3. Set Up Cameras

```bash
# Detect and configure cameras
sudo ./scripts/camera-setup.sh

# Test camera functionality
sudo ./scripts/camera-test.sh

# Verify QSV support
sudo ./scripts/test-qsv.sh
```

### 4. Start Recording

```bash
# Start recording service
sudo systemctl start dual-camera-record

# Enable auto-start
sudo systemctl enable dual-camera-record

# Check status
sudo systemctl status dual-camera-record
```

## Manual Configuration

### Camera Device Mapping

If cameras don't map correctly to `/dev/video0` and `/dev/video2`, you may need to:

1. **Identify your cameras:**
   ```bash
   lsusb
   v4l2-ctl --list-devices
   ```

2. **Create custom udev rules:**
   ```bash
   # Get camera details
   udevadm info -a -p $(udevadm info -q path -n /dev/video0)
   
   # Edit udev rules
   sudo nano /etc/udev/rules.d/99-camera-mapping.rules
   ```

3. **Example udev rule:**
   ```
   SUBSYSTEM=="video4linux", ATTRS{idVendor}=="0c45", ATTRS{idProduct}=="636d", SYMLINK+="video-cam1"
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

- **Higher quality (larger files):** `ENCODING_QUALITY="22"`
- **Balanced (default):** `ENCODING_QUALITY="28"`
- **Smaller files:** `ENCODING_QUALITY="32"`

### Resolution Settings

For different resolutions, modify:
```bash
CAMERA1_RESOLUTION="1920x1080"  # 1080p
CAMERA2_RESOLUTION="2560x1440"  # 1440p
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

# View recording logs
journalctl -u dual-camera-record -f

# Check disk usage
df -h /storage/recordings

# View recent recordings
ls -la /storage/recordings/cam1/ | tail -5
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

# Test camera manually
v4l2-ctl --list-devices
```

**2. QSV not working:**
```bash
# Check Intel GPU
lspci | grep Intel
vainfo

# Test QSV encoding
sudo ./scripts/test-qsv.sh
```

**3. Recording service fails:**
```bash
# Check service status
systemctl status dual-camera-record

# View error logs
journalctl -u dual-camera-record --since "1 hour ago"

# Test manual recording
sudo /usr/local/bin/dual-camera-record.sh
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
# Reset service
sudo systemctl stop dual-camera-record
sudo systemctl disable dual-camera-record
sudo systemctl daemon-reload
sudo systemctl enable dual-camera-record
sudo systemctl start dual-camera-record
```

**Corrupted recordings:**
```bash
# Check file integrity
find /storage/recordings -name "*.mp4" -exec ffprobe {} \; 2>&1 | grep -i error

# Remove corrupted files
find /storage/recordings -name "*.mp4" -size -1M -delete
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
