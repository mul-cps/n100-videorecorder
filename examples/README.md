# API Examples

This directory contains example scripts showing how to use the camera_recorder Python API in your own applications.

## Note

The `api_usage.py` file contains **illustrative examples** showing the general API pattern. Some method signatures may differ from the actual implementation. For production use, please refer to the actual module implementations in `src/camera_recorder/`.

## Actual API Usage

### Basic Recording

```python
from camera_recorder.main import CameraRecorderApp

# Create and run app
app = CameraRecorderApp(config_path='/etc/camera-recorder/config.yaml')

# Validate before running
if app.validate_system():
    # Run recording (blocks until stopped)
    app.run()
```

### Camera Detection

```python
from camera_recorder.camera import CameraDetector

detector = CameraDetector()
cameras = detector.detect_cameras()

# cameras is a List[CameraDevice]
for camera in cameras:
    print(f"Device: {camera.device}")
    print(f"Name: {camera.name}")
    print(f"Formats: {camera.formats}")
```

### Configuration Management

```python
from camera_recorder.config import SystemConfig

# Load from YAML
config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')

# Load from legacy bash config
config = SystemConfig.from_legacy_conf('/etc/camera-recorder/camera-mapping.conf')

# Convert to YAML
config.to_yaml('/tmp/config.yaml')

# Access settings
print(config.cameras['cam1'].resolution)
print(config.encoding.codec)
print(config.recording.segment_time)
```

### Storage Management

```python
from camera_recorder.storage import StorageManager
from camera_recorder.config import SystemConfig

config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')
storage = StorageManager(
    base_directory=config.recording.recordings_path,
    cleanup_days=config.storage.cleanup_days,
    disk_threshold=config.storage.disk_usage_threshold
)

# Run cleanup
removed, freed = storage.cleanup_old_recordings(dry_run=False)
print(f"Removed {removed} files, freed {freed / (1024**3):.2f} GB")

# Check disk usage
usage_percent = storage.check_disk_usage()
print(f"Disk usage: {usage_percent:.1f}%")
```

### Recording with Custom Configuration

```python
from camera_recorder.config import (
    CameraConfig, EncodingConfig, RecordingConfig, 
    StorageConfig, SystemConfig
)
from camera_recorder.recorder import FFmpegRecorder
from pathlib import Path

# Build configuration
camera_config = CameraConfig(
    device='/dev/video0',
    name='Test Camera',
    resolution='1920x1080',
    framerate=30,
    input_format='h264',
    enabled=True
)

encoding_config = EncodingConfig(codec='copy')

recording_config = RecordingConfig(
    segment_time=300,
    base_directory='/tmp/recordings'
)

# Create recorder
recorder = FFmpegRecorder(
    camera_id='test_cam',
    camera_config=camera_config,
    encoding_config=encoding_config,
    recording_config=recording_config
)

# Start recording
recorder.start_recording()

# ... let it record ...

# Stop recording
recorder.stop_recording()
```

## CLI Usage

For most use cases, the CLI is the recommended interface:

```bash
# Start recording
camera-recorder

# Detect cameras
camera-recorder --detect

# Validate configuration
camera-recorder --validate

# Show statistics
camera-recorder --stats

# Run cleanup
camera-recorder --cleanup
```

## Production Usage

For production use, it's recommended to:

1. Use the SystemD service (see `systemd/camera-recorder-python.service`)
2. Configure via YAML file (see `config.yaml.example`)
3. Monitor via `journalctl -u camera-recorder -f`
4. Manage via `systemctl` commands

## Further Reading

- See `src/camera_recorder/main.py` for the main application logic
- See `src/camera_recorder/*.py` for individual module implementations
- See `PYTHON_README.md` for complete documentation
- See type hints in the code for exact method signatures
