# N100 Video Recorder

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

2. **Configure cameras**:
   ```bash
   sudo ./scripts/setup-cameras.sh
   ```

3. **Start recording**:
   ```bash
   sudo systemctl start dual-camera-record
   sudo systemctl enable dual-camera-record
   ```

## Performance

With Intel QSV on N100:
- **CPU Usage**: 15-25% (vs 30-40% with VA-API)
- **Power Consumption**: 10-12W (vs 12-15W with VA-API)  
- **Quality**: Superior at same bitrate
- **Stability**: Excellent with fewer artifacts

## Directory Structure

```
/storage/recordings/
├── cam1/           # Camera 1 recordings
├── cam2/           # Camera 2 recordings
└── logs/           # Recording logs
```

## Configuration

### Camera Settings
- **Resolution**: 3840x2160 (4K)
- **Frame Rate**: 30 FPS
- **Format**: MJPEG input → H.265 output
- **Bitrate**: Variable (CQP mode, quality 28)
- **Segment Length**: 1 hour

### Storage Management
- Automatic cleanup after 30 days (configurable)
- Low disk space protection (stops recording at 95% full)

## Remote Access

The system is configured for remote management via:
- SSH (key-based authentication)
- Tailscale VPN (optional)
- Web interface for log viewing

## Troubleshooting

### Check Camera Status
```bash
./scripts/check-cameras.sh
```

### View Logs
```bash
journalctl -u dual-camera-record -f
```

### Test QSV
```bash
./scripts/test-qsv.sh
```

## License

MIT License - See LICENSE file for details.
