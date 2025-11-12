# N100 Video Recorder

> **🐍 Python Version Available!** A sophisticated Python rewrite is available on the `feature/python-rewrite` branch with improved error handling, validation, and monitoring. See [PYTHON_README.md](PYTHON_README.md) and [MIGRATION.md](MIGRATION.md) for details.

A complete solution for dual 4K USB camera recording on Intel N100 mini PC using Intel Quick Sync Video (QSV) hardware acceleration.

## Features

- **Intel QSV Hardware Acceleration**: Optimized for N100 processor with significantly lower CPU usage
- **Dual 4K Camera Support**: Simultaneous recording from two USB cameras
- **Auto-segmentation**: 1-hour video segments with automatic file management  
- **H.265/HEVC Encoding**: Efficient compression with hardware acceleration
- **Automated Deployment**: One-script setup for quick deployment
- **WiFi Pre-configuration**: Network setup included in deployment
- **USB Camera Mapping**: Automatic camera detection and persistent mapping
- **Systemd Integration**: Reliable service management with auto-restart
- **Remote Management**: Tailscale-ready for remote access

## System Requirements

- Intel N100 mini PC
- Ubuntu 22.04 LTS or newer
- Two USB 4K cameras
- At least 1TB storage
- WiFi capability

## Quick Start

1. **Clone and deploy**:
   ```bash
   git clone <your-repo-url>
   cd n100-videorecorder
   sudo ./deploy.sh
   ```

2. **Detect and configure cameras**:
   ```bash
   sudo ./scripts/detect-cameras.sh
   # Edit configuration based on detected cameras
   sudo nano /etc/camera-recorder/camera-mapping.conf
   ```

3. **Copy and enable systemd service**:
   ```bash
   sudo cp systemd/dual-camera-record.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable dual-camera-record
   sudo systemctl start dual-camera-record
   ```

4. **Verify setup**:
   ```bash
   sudo ./verify-setup.sh
   journalctl -u dual-camera-record -f
   ```

## Performance

With Intel QSV on N100 (when encoding, not stream copy mode):
- **CPU Usage**: 15-25% (vs 30-40% with VA-API)
- **Power Consumption**: 10-12W (vs 12-15W with VA-API)  
- **Quality**: Superior at same bitrate
- **Stability**: Excellent with fewer artifacts

**Stream Copy Mode** (current default):
- **CPU Usage**: 2-5% (no transcoding)
- **No quality loss**: Direct H.264 stream from cameras
- **Lower latency**: Minimal processing overhead
- **Highest reliability**: Simple remuxing to MP4 segments

## Directory Structure

```
/storage/recordings/
├── cam1/           # Camera 1 recordings (30-minute segments)
├── cam2/           # Camera 2 recordings (30-minute segments)
└── logs/           # Recording logs (deprecated - see journalctl)

Logs: journalctl -u dual-camera-record
```

## Configuration

The main configuration file is `/etc/camera-recorder/camera-mapping.conf` (after deployment).

### Current Camera Settings (Optimized for Conveyor Belt/Fast Motion)
- **Resolution**: 2560x1440 (1440p) - configurable
- **Frame Rate**: 60 FPS (was 30, increased for motion clarity)
- **Input Format**: H.264 from cameras
- **Output Codec**: Stream copy (no transcoding) or H.265 QSV
- **Bitrate**: VBR mode with 8-12 Mbps per camera
- **Quality**: CQP 23 (high quality for detail preservation)
- **Segment Length**: 1800 seconds (30-minute segments)
- **GOP Size**: 60 frames (1 keyframe per second)

### Camera Device Mapping
Cameras use persistent symlinks based on USB bus position:
- **Camera 1**: `/dev/video-usb1-video0` (fallback: `/dev/video0`)
- **Camera 2**: `/dev/video-usb2-video3` (fallback: `/dev/video2`)

This ensures cameras stay mapped correctly even after reboots.

### Storage Management
- Automatic cleanup after 30 days (configurable)
- Low disk space protection (stops recording at 95% full)
- Buffered disk writes for reduced I/O frequency

## Remote Access

The system is configured for remote management via:
- SSH (key-based authentication recommended)
- Tailscale VPN (optional, for secure remote access)
- Web interface for monitoring (optional, port 8080)

See `docs/` for web interface setup using nginx or Python Flask.

## Troubleshooting

### Check Camera Status
```bash
./scripts/check-cameras.sh
# or detect available cameras:
./scripts/detect-cameras.sh
```

### View Logs
```bash
journalctl -u dual-camera-record -f
# or check specific camera logs:
tail -f /var/log/camera-recorder/camera1-qsv.log
tail -f /var/log/camera-recorder/camera2-qsv.log
```

### Test QSV (if using hardware encoding)
```bash
./scripts/test-qsv.sh
```

### Check USB Bandwidth
```bash
./scripts/usb-bandwidth-test.sh
```

## Additional Documentation

- **DEPLOYMENT.md** - Detailed deployment and configuration guide
- **CONFIGURATION_UPDATE.md** - Recent configuration changes and web interface
- **CONVEYOR_BELT_OPTIMIZATION.md** - Settings optimized for fast motion capture
- **GRACEFUL_SHUTDOWN.md** - Information about proper service shutdown

## Important Notes

1. **User Configuration**: The systemd service file references `bjoern` as the user. Update this in `systemd/dual-camera-record.service` to match your username before deployment.

2. **Camera Devices**: The system uses persistent symlinks (e.g., `/dev/video-usb1-video0`) created by udev rules. If cameras aren't detected, check `/dev/video*` devices and update camera-mapping.conf accordingly.

3. **Recording Mode**: By default, the system uses stream copy mode (`ENCODING_CODEC="copy"`) for H.264 cameras, which provides zero-latency recording with no quality loss. Change to `hevc_qsv` for hardware-accelerated H.265 encoding if needed.

## Python Implementation

For a more sophisticated implementation with better error handling, validation, and monitoring capabilities:

- **Documentation**: See [PYTHON_README.md](PYTHON_README.md) for complete Python version documentation
- **Migration Guide**: See [MIGRATION.md](MIGRATION.md) for step-by-step migration from bash to Python
- **Quick Reference**: See [PYTHON_QUICK_REFERENCE.md](PYTHON_QUICK_REFERENCE.md) for daily operation commands
- **Branch**: `feature/python-rewrite`

The Python version offers:
- Automatic camera detection and validation
- YAML-based configuration with schema validation
- Built-in health monitoring and statistics
- Unified CLI interface (`camera-recorder`)
- Comprehensive error handling and logging
- Dry-run capabilities for testing

## License

MIT License - See LICENSE file for details.
