# Conveyor Belt Recording Optimization

## Overview

The camera recording system has been optimized for capturing fast-moving conveyor belts with small particles. These settings prioritize **detail preservation** and **motion clarity** over file size.

## Optimizations Applied

### 1. **Higher Quality Encoding**
- **Quality Setting**: `23` (was `28`)
  - Lower numbers = better quality
  - Preserves fine details of small particles
  - Reduces compression artifacts

### 2. **Faster Encoding Preset**
- **Preset**: `fast` (was `medium`)
  - Better motion handling
  - Less motion blur on fast-moving objects
  - Faster encoding = lower latency

### 3. **Variable Bitrate (VBR) Mode**
- **Target Bitrate**: `15 Mbps` per camera
- **Max Bitrate**: `20 Mbps` per camera
- Automatically allocates more bits to complex scenes (particles in motion)
- Ensures consistent quality regardless of content

### 4. **Optimized GOP Structure**
- **GOP Size**: `60` frames (1 second at 60fps)
  - More frequent keyframes
  - Better seek accuracy
  - Faster recovery from transmission errors
  - Less temporal compression = clearer motion

### 5. **Enhanced Motion Estimation**
- **Reference Frames**: `3`
- **B-Frames**: `3`
- **Lookahead**: Enabled
  - Better prediction of particle movement
  - Improved quality for fast motion scenes
  - Optimizes bitrate allocation

### 6. **60 FPS Capture**
- **Frame Rate**: `60 fps` (was `30 fps`)
  - Smoother motion
  - Better temporal resolution for particle tracking
  - Reduced motion blur
  - More data for computer vision analysis

## Expected Results

### File Sizes (per camera):
- **1 minute @ 4K 60fps**: ~110-150 MB
- **1 hour**: ~6.6-9 GB
- **24 hours**: ~158-216 GB

### Quality Benefits:
1. **Particle Detail**: Small particles clearly visible
2. **Motion Clarity**: Individual particles trackable frame-to-frame
3. **Reduced Blur**: Minimal motion blur even at high belt speeds
4. **Consistent Quality**: VBR ensures quality in busy scenes

### Performance:
- **CPU Usage**: ~40-60% on Intel N100 (dual cameras)
- **Encoding Latency**: ~50-100ms per camera
- **GPU Usage**: ~30-50% (QSV hardware acceleration)

## Configuration Details

### From `config/camera-mapping.conf`:

```bash
# Frame rate for smooth motion
CAMERA1_FRAMERATE="60"
CAMERA2_FRAMERATE="60"

# Fast preset for better motion handling
ENCODING_PRESET="fast"

# High quality for detail preservation
ENCODING_QUALITY="23"

# VBR mode for consistent quality
BITRATE_MODE="VBR"
TARGET_BITRATE="15000"    # 15 Mbps
MAX_BITRATE="20000"       # 20 Mbps

# GOP structure optimized for motion
GOP_SIZE="60"             # 1 keyframe per second
REF_FRAMES="3"            # 3 reference frames for motion estimation

# Lookahead for better quality prediction
LOOKAHEAD_ENABLED="1"
```

## Use Cases

### Optimal for:
- ✅ Particle tracking and analysis
- ✅ Quality control inspection
- ✅ Debris detection
- ✅ Size/shape classification
- ✅ Color detection
- ✅ Speed measurement
- ✅ Computer vision / AI processing

### Settings provide:
- **High detail**: Capture particles as small as 2-3 pixels
- **Motion clarity**: Track individual particles across frames
- **Temporal accuracy**: 16.67ms between frames (60fps)
- **Reliable data**: Consistent quality for automated analysis

## Tuning Guide

### If you need MORE quality (larger files):
```bash
# In /etc/camera-recorder/camera-mapping.conf
ENCODING_QUALITY="20"        # Even higher quality
TARGET_BITRATE="20000"       # 20 Mbps
MAX_BITRATE="30000"          # 30 Mbps max
```

### If you need SMALLER files (lower quality):
```bash
ENCODING_QUALITY="26"        # Lower quality
TARGET_BITRATE="10000"       # 10 Mbps
MAX_BITRATE="15000"          # 15 Mbps max
```

### If motion blur is still visible:
```bash
# Increase shutter speed on cameras (hardware setting)
# Or increase frame rate to 120fps if cameras support it:
CAMERA1_FRAMERATE="120"
CAMERA2_FRAMERATE="120"
GOP_SIZE="120"               # Match GOP to framerate
```

### If particles are too small to see:
```bash
# Increase resolution or zoom cameras closer
# Or reduce compression:
ENCODING_QUALITY="18"        # Very high quality
ENCODING_PRESET="slow"       # Slower but better quality
```

## Storage Calculations

### Daily Storage Requirements:

| Configuration | Per Camera | Both Cameras | Weekly | Monthly |
|---------------|------------|--------------|--------|---------|
| Current (60fps, Q23) | 158-216 GB | 316-432 GB | 2.2-3.0 TB | 9.5-13 TB |
| Reduced (30fps, Q26) | 60-90 GB | 120-180 GB | 840 GB-1.3 TB | 3.6-5.4 TB |
| Maximum (60fps, Q20) | 200-280 GB | 400-560 GB | 2.8-3.9 TB | 12-17 TB |

### Storage Recommendations:
- **Minimum**: 2 TB SSD/NVMe for 3-5 days retention
- **Recommended**: 8-10 TB HDD for 2-3 weeks retention
- **Optimal**: 20+ TB RAID array for 4+ weeks retention

## Computer Vision Integration

These settings are optimized for post-processing with:
- OpenCV
- TensorFlow / PyTorch
- YOLO / Faster R-CNN object detection
- Optical flow analysis
- Particle tracking algorithms

### Benefits for CV:
1. **60 fps** = better optical flow estimation
2. **High quality** = more accurate feature detection
3. **Short GOPs** = easier random access for frame extraction
4. **HEVC** = smaller files than H.264 at same quality

### Example Python extraction:
```python
import cv2

cap = cv2.VideoCapture('/storage/recordings/cam1/cam1_20251112_120000.mp4')
fps = cap.get(cv2.CAP_PROP_FPS)  # 60.0
frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)  # ~3600 frames (60 seconds)

# Extract every 10th frame for analysis
frame_num = 0
while True:
    ret, frame = cap.read()
    if not ret:
        break
    if frame_num % 10 == 0:
        # Process frame for particle detection
        process_particles(frame)
    frame_num += 1
```

## Deployment

To apply these settings:

```bash
# 1. Update config file
sudo cp /home/bjoern/git/n100-videorecorder/config/camera-mapping.conf /etc/camera-recorder/camera-mapping.conf

# 2. Restart recording service
sudo systemctl restart dual-camera-record.service

# 3. Verify settings in logs
sudo journalctl -u dual-camera-record.service -f
```

## Monitoring Quality

### Check actual bitrate of recordings:
```bash
# Using FFmpeg
ffmpeg -i /storage/recordings/cam1/cam1_20251112_120000.mp4 2>&1 | grep "bitrate"

# Using mediainfo (install: sudo apt install mediainfo)
mediainfo /storage/recordings/cam1/cam1_20251112_120000.mp4 | grep -E "(Bit rate|Frame rate)"
```

### Expected output:
```
Overall bit rate : 15.0 Mb/s
Frame rate : 60.000 FPS
```

### Quality verification:
```bash
# Extract a few frames to check detail
ffmpeg -i /storage/recordings/cam1/cam1_20251112_120000.mp4 -vframes 5 -q:v 2 frame_%03d.png

# View frames to check particle visibility
display frame_001.png  # or use any image viewer
```

## Troubleshooting

### If encoding can't keep up (dropped frames):
1. Reduce quality: `ENCODING_QUALITY="26"`
2. Use faster preset: `ENCODING_PRESET="veryfast"`
3. Reduce bitrate: `TARGET_BITRATE="10000"`
4. Check CPU usage: `htop`

### If files are too large:
1. Increase quality value: `ENCODING_QUALITY="26"` or `"28"`
2. Reduce target bitrate: `TARGET_BITRATE="10000"`
3. Consider H.264 instead of HEVC: `ENCODING_CODEC="h264_qsv"`

### If motion is still blurry:
1. Check camera shutter speed (hardware)
2. Ensure cameras are at 60fps: `v4l2-ctl --device=/dev/video0 --all | grep "Frame rate"`
3. Increase frame rate if supported: `CAMERA1_FRAMERATE="120"`

## Comparison: Before vs After

| Setting | Before (General) | After (Conveyor Belt) |
|---------|------------------|----------------------|
| Frame Rate | 30 fps | **60 fps** |
| Quality | 28 | **23** (higher) |
| Preset | medium | **fast** (better motion) |
| Bitrate | CQP only | **VBR 15-20 Mbps** |
| GOP Size | 90 (3s) | **60** (1s) |
| Reference Frames | Default (1) | **3** |
| Lookahead | Off | **On** |
| File Size | ~30 MB/min | ~110-150 MB/min |
| Detail Level | Medium | **High** |
| Motion Clarity | Good | **Excellent** |

