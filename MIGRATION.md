# Migration Guide: Bash to Python

This guide helps you migrate from the bash-based implementation to the sophisticated Python version.

## 🎯 Why Migrate?

### Benefits of Python Version

| Feature | Improvement |
|---------|------------|
| **Error Handling** | Comprehensive validation and error recovery |
| **Configuration** | YAML format with schema validation |
| **Monitoring** | Built-in health checks and statistics |
| **Extensibility** | Modular architecture, easy to add features |
| **Maintenance** | Cleaner code, easier to understand and modify |
| **Testing** | Unit testable components |
| **CLI** | Unified interface with multiple commands |

### What Stays the Same

- Recording quality and settings (30-min segments, 1440p@60fps)
- Storage structure (`/storage/recordings/camX/`)
- FFmpeg encoding parameters
- SystemD service integration
- Udev camera mapping rules
- Performance (FFmpeg processes are identical)

## 📋 Prerequisites

Before migrating:

1. **Python 3.8+** is installed:
   ```bash
   python3 --version  # Should be 3.8 or higher
   ```

2. **Current system is working**:
   ```bash
   sudo systemctl status dual-camera-record
   # Should be active and recording
   ```

3. **Backup current configuration**:
   ```bash
   sudo cp /etc/camera-recorder/camera-mapping.conf /etc/camera-recorder/camera-mapping.conf.backup
   ```

## 🔄 Migration Steps

### Step 1: Install Python Package

```bash
cd /home/bjoern/git/n100-videorecorder

# Ensure you're on the feature/python-rewrite branch
git checkout feature/python-rewrite

# Install the package in development mode
pip3 install -e .

# Verify installation
camera-recorder --version  # Should show version 2.0.0
```

### Step 2: Convert Configuration

#### Option A: Use Legacy Config Directly

The Python version can read the old bash config:

```bash
# Test with legacy config
camera-recorder --config /etc/camera-recorder/camera-mapping.conf --validate

# If validation passes, you can use it as-is
camera-recorder --config /etc/camera-recorder/camera-mapping.conf
```

#### Option B: Convert to YAML (Recommended)

```bash
# Convert to YAML
python3 << 'EOF'
from camera_recorder.config import SystemConfig

# Load legacy configuration
config = SystemConfig.from_legacy_conf('/etc/camera-recorder/camera-mapping.conf')

# Save as YAML
config.to_yaml('/etc/camera-recorder/config.yaml')

print("✓ Configuration converted to /etc/camera-recorder/config.yaml")
EOF

# Make it readable by your user
sudo chown $USER:$USER /etc/camera-recorder/config.yaml
```

#### Option C: Start Fresh with Example

```bash
# Copy example configuration
sudo cp config.yaml.example /etc/camera-recorder/config.yaml

# Edit to match your setup
sudo nano /etc/camera-recorder/config.yaml
```

### Step 3: Validate New Configuration

```bash
# Detect cameras to verify device paths
camera-recorder --detect

# Validate configuration
camera-recorder --validate

# Expected output:
# ✓ Storage directory accessible
# ✓ Sufficient disk space
# ✓ Camera cam1: All checks passed
# ✓ Camera cam2: All checks passed
# ✓ System validation passed
```

### Step 4: Test Recording (Parallel Run)

Run both versions simultaneously to compare:

```bash
# Keep bash version running
sudo systemctl status dual-camera-record  # Should be active

# Test Python version in foreground (30 seconds)
timeout 30s camera-recorder --config /etc/camera-recorder/config.yaml

# Check if files were created
ls -lh /storage/recordings/cam1/ | tail
ls -lh /storage/recordings/cam2/ | tail

# Compare FFmpeg parameters
ps aux | grep ffmpeg  # Check both versions use same parameters
```

### Step 5: Stop Bash Service

```bash
# Stop the bash version
sudo systemctl stop dual-camera-record

# Disable it (don't delete yet)
sudo systemctl disable dual-camera-record

# Verify it's stopped
sudo systemctl status dual-camera-record
```

### Step 6: Install Python Service

```bash
# Copy Python service file
sudo cp systemd/camera-recorder-python.service /etc/systemd/system/camera-recorder.service

# Edit to match your username and paths
sudo nano /etc/systemd/system/camera-recorder.service

# Key settings to verify:
# - User=bjoern (your username)
# - ExecStart path to config.yaml
# - WorkingDirectory if needed

# Reload systemd
sudo systemctl daemon-reload

# Enable Python service
sudo systemctl enable camera-recorder

# Start it
sudo systemctl start camera-recorder

# Check status
sudo systemctl status camera-recorder
```

### Step 7: Monitor and Verify

```bash
# Watch logs in real-time
journalctl -u camera-recorder -f

# In another terminal, check statistics
camera-recorder --stats

# Verify recordings are being created
watch -n 5 'ls -lh /storage/recordings/cam1/ | tail -3'

# Check disk usage
df -h /storage
```

### Step 8: Cleanup (Optional)

After successful migration and 1-2 weeks of stable operation:

```bash
# Remove old service file
sudo rm /etc/systemd/system/dual-camera-record.service
sudo systemctl daemon-reload

# Archive bash scripts (don't delete, keep for reference)
mkdir -p ~/archive/n100-videorecorder-bash
cp -r scripts ~/archive/n100-videorecorder-bash/

# Keep the legacy config as backup
# Don't delete camera-mapping.conf in case you need to rollback
```

## 🔧 Configuration Mapping

### Bash → YAML Equivalents

| Bash Variable | YAML Path | Notes |
|---------------|-----------|-------|
| `CAMERA1_DEVICE` | `cameras.cam1.device` | Device path |
| `CAMERA1_NAME` | `cameras.cam1.name` | Human-readable name |
| `CAMERA2_DEVICE` | `cameras.cam2.device` | Device path |
| `CAMERA2_NAME` | `cameras.cam2.name` | Human-readable name |
| `RESOLUTION` | `cameras.*.resolution` | Format: "2560x1440" |
| `FRAMERATE` | `cameras.*.framerate` | Integer: 60 |
| `INPUT_FORMAT` | `cameras.*.input_format` | "h264", "mjpeg", etc. |
| `ENCODING_CODEC` | `encoding.codec` | "copy", "hevc_qsv", etc. |
| `QSV_PRESET` | `encoding.preset` | QSV preset |
| `QSV_QUALITY` | `encoding.quality` | Quality/CRF value |
| `SEGMENT_TIME` | `recording.segment_time` | Seconds: 1800 |
| `OUTPUT_BASE` | `recording.base_directory` | Base directory path |
| `CLEANUP_DAYS` | `storage.cleanup_days` | Integer: 30 |
| `DISK_THRESHOLD` | `storage.disk_usage_threshold` | Percentage: 95 |

### Example Conversion

**Bash Config** (`camera-mapping.conf`):
```bash
CAMERA1_DEVICE="/dev/video-usb1-video0"
CAMERA1_NAME="Primary Camera"
CAMERA2_DEVICE="/dev/video-usb2-video3"
CAMERA2_NAME="Secondary Camera"
RESOLUTION="2560x1440"
FRAMERATE="60"
INPUT_FORMAT="h264"
ENCODING_CODEC="copy"
SEGMENT_TIME="1800"
OUTPUT_BASE="/storage/recordings"
CLEANUP_DAYS="30"
```

**YAML Config** (`config.yaml`):
```yaml
cameras:
  cam1:
    device: "/dev/video-usb1-video0"
    name: "Primary Camera"
    resolution: "2560x1440"
    framerate: 60
    input_format: "h264"
    enabled: true
  cam2:
    device: "/dev/video-usb2-video3"
    name: "Secondary Camera"
    resolution: "2560x1440"
    framerate: 60
    input_format: "h264"
    enabled: true

encoding:
  codec: "copy"

recording:
  segment_time: 1800
  base_directory: "/storage/recordings"

storage:
  cleanup_enabled: true
  cleanup_days: 30
```

## 🎛️ Feature Comparison

### What Changed

| Feature | Bash | Python |
|---------|------|--------|
| **Main Script** | `dual-camera-record.sh` | `camera-recorder` CLI |
| **Config File** | `/etc/camera-recorder/camera-mapping.conf` | `/etc/camera-recorder/config.yaml` |
| **Service Name** | `dual-camera-record.service` | `camera-recorder.service` |
| **Detection** | `detect-cameras.sh` | `camera-recorder --detect` |
| **Testing** | `camera-test.sh` | `camera-recorder --validate` |
| **Cleanup** | `cleanup-recordings.sh` | `camera-recorder --cleanup` |
| **Stats** | Manual `du` commands | `camera-recorder --stats` |

### New Features in Python

1. **Pre-flight Validation**: `camera-recorder --validate`
   - Checks camera accessibility
   - Validates format support
   - Verifies storage availability
   - Tests disk space

2. **Automatic Camera Detection**: `camera-recorder --detect`
   - Lists all cameras
   - Shows supported formats
   - Recommends optimal configuration
   - Detects symlinks

3. **Rich Statistics**: `camera-recorder --stats`
   - Total files and sizes
   - Per-camera breakdown
   - Disk usage monitoring
   - Latest recording info

4. **Dry-run Cleanup**: `camera-recorder --cleanup --dry-run`
   - Preview what would be deleted
   - Safety before actual cleanup

5. **Health Monitoring**:
   - Continuous process monitoring
   - Automatic emergency cleanup
   - Self-healing capabilities

6. **Unified CLI**:
   - Single command for all operations
   - Consistent interface
   - Built-in help: `camera-recorder --help`

## 🔄 Rollback Plan

If you need to revert to the bash version:

### Quick Rollback

```bash
# Stop Python service
sudo systemctl stop camera-recorder
sudo systemctl disable camera-recorder

# Re-enable bash service
sudo systemctl enable dual-camera-record
sudo systemctl start dual-camera-record

# Verify it's running
sudo systemctl status dual-camera-record
journalctl -u dual-camera-record -f
```

### Full Rollback

```bash
# Switch back to main branch
cd /home/bjoern/git/n100-videorecorder
git checkout main

# Restore old service
sudo systemctl stop camera-recorder
sudo systemctl disable camera-recorder
sudo rm /etc/systemd/system/camera-recorder.service

sudo systemctl enable dual-camera-record
sudo systemctl start dual-camera-record
sudo systemctl daemon-reload

# Restore old config if needed
sudo cp /etc/camera-recorder/camera-mapping.conf.backup /etc/camera-recorder/camera-mapping.conf

# Verify
sudo systemctl status dual-camera-record
```

## 🐛 Troubleshooting

### Python Service Won't Start

```bash
# Check service logs
journalctl -u camera-recorder -n 50

# Common issues:
# 1. Import errors - ensure package is installed
pip3 show camera-recorder

# 2. Config file not found - check path in service file
cat /etc/systemd/system/camera-recorder.service | grep ExecStart

# 3. Permission errors - check user/group
ls -la /etc/camera-recorder/config.yaml
```

### Configuration Errors

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/camera-recorder/config.yaml'))"

# Run validation
camera-recorder --validate

# Compare with example
diff /etc/camera-recorder/config.yaml config.yaml.example
```

### Cameras Not Detected

```bash
# Check device files exist
ls -la /dev/video-usb*

# Re-run udev rules if needed
sudo udevadm control --reload-rules
sudo udevadm trigger

# Run detection
camera-recorder --detect

# Check v4l2 directly
v4l2-ctl --list-devices
```

### Recording Not Working

```bash
# Check FFmpeg parameters in logs
journalctl -u camera-recorder | grep ffmpeg

# Test FFmpeg manually with same parameters
# (copy from logs)

# Verify disk space
df -h /storage

# Check directory permissions
ls -la /storage/recordings
```

## 📊 Performance Comparison

Both versions use identical FFmpeg processes, so performance is the same:

| Metric | Bash | Python | Notes |
|--------|------|--------|-------|
| **CPU Usage** | ~2-3% | ~2-3% | FFmpeg encoding |
| **Memory** | ~100 MB | ~120 MB | +20 MB for Python runtime |
| **Startup Time** | ~2s | ~3s | +1s for Python initialization |
| **Recording Quality** | Identical | Identical | Same FFmpeg parameters |
| **Segment Timing** | Identical | Identical | Same 30-min segments |

The Python overhead is minimal and provides significant benefits in maintainability and features.

## ✅ Migration Checklist

- [ ] Python 3.8+ installed and verified
- [ ] Current bash system backed up
- [ ] Configuration backed up
- [ ] Python package installed (`pip3 install -e .`)
- [ ] Configuration converted or created
- [ ] Configuration validated (`camera-recorder --validate`)
- [ ] Test recording completed successfully
- [ ] Service file copied and edited
- [ ] Bash service stopped
- [ ] Python service started
- [ ] Logs monitored for 24 hours
- [ ] Recordings verified for 1 week
- [ ] Statistics checked (`camera-recorder --stats`)
- [ ] Cleanup tested (`camera-recorder --cleanup --dry-run`)
- [ ] Old service files archived
- [ ] Documentation updated

## 📞 Support

If you encounter issues during migration:

1. Check logs: `journalctl -u camera-recorder -f`
2. Run validation: `camera-recorder --validate`
3. Compare configs side-by-side
4. Test cameras: `camera-recorder --detect`
5. Rollback if needed (see Rollback Plan above)

## 🎉 Post-Migration

After successful migration:

1. **Monitor for a week**: Ensure stability
2. **Test all features**: Detection, validation, stats, cleanup
3. **Update documentation**: Note any custom changes
4. **Share feedback**: Document any issues or improvements
5. **Plan enhancements**: Consider adding new features (web UI, API, etc.)

The Python version provides a solid foundation for future enhancements!
