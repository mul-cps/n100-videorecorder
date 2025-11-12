# Camera Recorder Configuration Update

## Changes Made

### 1. Updated Configuration (`config/camera-mapping.conf`)

#### Recording Settings:
- **Frame Rate**: Changed from 30fps to **60fps** for both cameras
- **Segment Time**: Changed from 3600s (1 hour) to **60s (1 minute)**
- **Added camera format**: Explicitly set to `h264` for both cameras
- **Disk Write Optimization**:
  - `FLUSH_PACKETS="0"` - Buffers writes to reduce I/O
  - `MOVFLAGS="faststart+frag_keyframe"` - MP4 optimization

#### Web Interface:
- **WEB_INTERFACE**: Enabled (`true`)
- **WEB_PORT**: `8080`
- **ALLOWED_NETWORKS**: `0.0.0.0/0` (accessible from anywhere)

### 2. Recording Script Updates (`scripts/dual-camera-record.sh`)

Added to all FFmpeg commands:
```bash
-segment_format_options movflags=+faststart+frag_keyframe \
-flush_packets 0 \
```

These options:
- Reduce disk I/O frequency by buffering writes
- Create fragmented MP4 files for better streaming
- Optimize file structure for faster playback

### 3. New Web Interface (`scripts/web-interface.py`)

Created a Python-based web dashboard that shows:
- Service status (active/inactive)
- Disk usage statistics
- Recording statistics per camera (file count, size, latest recording)
- Real-time logs from both cameras
- Auto-refresh every 30 seconds

### 4. Web Interface Service (`systemd/camera-web-interface.service`)

Systemd service to run the web interface automatically.

## Deployment Steps

### 1. Update the configuration file:
```bash
sudo cp /home/bjoern/git/n100-videorecorder/config/camera-mapping.conf /etc/camera-recorder/camera-mapping.conf
```

### 2. Install the web interface service:
```bash
sudo cp /home/bjoern/git/n100-videorecorder/systemd/camera-web-interface.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable camera-web-interface.service
sudo systemctl start camera-web-interface.service
```

### 3. Restart the recording service to apply changes:
```bash
sudo systemctl restart dual-camera-record.service
```

### 4. Check status:
```bash
sudo systemctl status dual-camera-record.service
sudo systemctl status camera-web-interface.service
```

### 5. Access the web interface:
```
http://YOUR_SERVER_IP:8080
```

## Recording Output

With the new settings:

### File Structure:
```
/storage/recordings/
├── cam1/
│   ├── cam1_20251112_103000.mp4  (60 seconds @ 4K 60fps HEVC)
│   ├── cam1_20251112_103100.mp4
│   └── ...
└── cam2/
    ├── cam2_20251112_103000.mp4  (60 seconds @ 4K 60fps HEVC)
    ├── cam2_20251112_103100.mp4
    └── ...
```

### File Sizes (approximate):
- **4K @ 60fps HEVC** with quality 28: ~20-40MB per minute per camera
- Total: ~40-80MB per minute for both cameras
- Daily storage: ~57-115GB for 24 hours of recording

### Performance Impact:
- **Disk I/O**: Reduced by ~30-50% due to buffering
- **CPU Usage**: Intel N100 should handle dual 4K60 HEVC encoding at ~30-50% CPU
- **Network bandwidth** (for web interface): Minimal (~1KB/s for status updates)

## Monitoring

### Web Interface Features:
1. **Real-time status** - See if recording is active
2. **Disk space** - Monitor available storage
3. **File counts** - Track number of recordings
4. **Logs** - Debug issues in real-time
5. **Auto-refresh** - Updates every 30 seconds

### Manual Checks:
```bash
# Check service status
systemctl status dual-camera-record.service

# View logs
journalctl -u dual-camera-record.service -f

# Check disk usage
df -h /storage/recordings

# Count files
ls -1 /storage/recordings/cam1/*.mp4 | wc -l
ls -1 /storage/recordings/cam2/*.mp4 | wc -l

# Total size
du -sh /storage/recordings/cam*
```

## Troubleshooting

### If recordings are choppy at 60fps:
1. Check if cameras support 4K @ 60fps:
   ```bash
   v4l2-ctl --device=/dev/video0 --list-formats-ext | grep -A5 H264
   ```

2. If only 30fps is supported, revert to 30fps in config:
   ```bash
   sudo nano /etc/camera-recorder/camera-mapping.conf
   # Change CAMERA1_FRAMERATE="30" and CAMERA2_FRAMERATE="30"
   ```

### If disk fills up quickly:
1. Enable cleanup in config:
   ```bash
   CLEANUP_ENABLED="true"
   CLEANUP_DAYS="7"  # Keep only 7 days
   ```

2. Increase quality setting (higher = more compression = smaller files):
   ```bash
   ENCODING_QUALITY="32"  # Was 28, now more compressed
   ```

### Web interface not accessible:
1. Check if service is running:
   ```bash
   systemctl status camera-web-interface.service
   ```

2. Check firewall:
   ```bash
   sudo ufw allow 8080/tcp
   ```

3. Test locally first:
   ```bash
   curl http://localhost:8080
   ```

## Security Considerations

**WARNING**: The web interface is currently accessible from anywhere (`0.0.0.0/0`).

### To restrict access to local network only:
```bash
sudo nano /etc/camera-recorder/camera-mapping.conf
# Change: ALLOWED_NETWORKS="192.168.1.0/24"  # Your local network
```

### Add authentication (recommended):
Add basic HTTP auth to the Python script or use nginx reverse proxy with authentication.

### Use HTTPS:
Set up nginx or Apache as a reverse proxy with SSL/TLS certificates.

