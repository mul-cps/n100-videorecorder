# Why FFmpeg Instead of OpenCV (cv2)?

## Executive Summary

This project uses **FFmpeg via subprocess** instead of Python libraries like OpenCV (cv2) because:

1. **Hardware Acceleration**: Direct access to Intel Quick Sync Video (QSV) on N100 processor
2. **Stream Copy Mode**: Zero-latency, zero-overhead recording from H.264 cameras
3. **Production Reliability**: Battle-tested for 24/7 industrial recording
4. **Performance**: <1% CPU usage vs 40-60% with cv2
5. **Simplicity**: Built-in segmentation, no frame-by-frame processing needed

## Detailed Comparison

### 1. Hardware Acceleration (Intel QSV)

**FFmpeg Approach:**
```bash
ffmpeg -hwaccel qsv -c:v hevc_qsv -i /dev/video0 output.mp4
```
- Direct access to Intel's GPU hardware encoders
- Zero-copy GPU memory operations
- ~2-3% CPU usage for HEVC encoding
- Native support in jellyfin-ffmpeg

**OpenCV Approach:**
```python
cap = cv2.VideoCapture('/dev/video0')
out = cv2.VideoWriter('output.mp4', cv2.VideoWriter_fourcc(*'H264'), ...)
```
- **No native QSV support** in cv2.VideoWriter
- Would require GStreamer pipeline integration (complex)
- Software encoding only → 40-60% CPU usage
- Defeats the entire purpose of N100's hardware capabilities

**Verdict**: ❌ OpenCV cannot access QSV hardware acceleration easily

### 2. Stream Copy Mode (Your Current Setup)

**FFmpeg Stream Copy:**
```bash
ffmpeg -f v4l2 -input_format h264 -i /dev/video0 -c:v copy output.mp4
```
- Cameras output native H.264 → FFmpeg remuxes to MP4
- **Zero CPU overhead** (<1% usage)
- **Zero latency** (no encoding delay)
- **Bit-perfect copy** (no quality loss)
- This is your current configuration with `ENCODING_CODEC="copy"`

**OpenCV Equivalent:**
```python
cap = cv2.VideoCapture('/dev/video0')
out = cv2.VideoWriter(...)
while True:
    ret, frame = cap.read()    # Decodes H.264 → BGR pixels (CPU intensive)
    out.write(frame)           # Re-encodes BGR → H.264 (CPU intensive)
```
- **Cannot do stream copy** - always decodes and re-encodes
- 40-60% CPU usage for dual 1440p@60fps cameras
- Adds ~50ms latency per frame
- Quality loss from re-encoding

**Verdict**: ❌ OpenCV fundamentally cannot do stream copy

### 3. Segmented Recording

**FFmpeg Built-in:**
```bash
-f segment -segment_time 1800 -segment_format mp4 -segment_format_options movflags=+faststart
```
- Native segmentation support
- Atomic file writes
- No frame drops during transitions
- Automatic filename generation

**OpenCV Manual:**
```python
start_time = time.time()
while recording:
    if time.time() - start_time > 1800:
        out.release()                    # Close current file
        out = cv2.VideoWriter(new_file)  # Open new file
        # Risk of dropped frames during transition!
```
- Manual time tracking
- Potential frame drops during file changes
- Complex error handling needed
- Must implement filename logic

**Verdict**: ❌ OpenCV requires manual segmentation with drop risk

### 4. Performance Comparison

| Metric | FFmpeg Stream Copy | FFmpeg QSV | OpenCV Software | OpenCV + GStreamer |
|--------|-------------------|-----------|----------------|-------------------|
| **CPU Usage (Dual 1440p@60fps)** | <1% | 2-3% | 40-60% | 10-20% |
| **Encoding Latency** | 0ms | ~10ms | ~50ms | ~30ms |
| **Quality Loss** | None | Minimal | Some | Minimal |
| **Setup Complexity** | Simple | Simple | Medium | Very Complex |
| **Dependencies** | FFmpeg only | FFmpeg only | opencv-python | opencv + gstreamer |
| **QSV Support** | ✅ Native | ✅ Native | ❌ None | ⚠️ Complex |
| **Production Ready** | ✅ Yes | ✅ Yes | ⚠️ For CV tasks | ⚠️ Fragile |

### 5. Resource Usage (Dual Camera Recording)

**Current FFmpeg Setup (Stream Copy):**
- CPU: <1% (just I/O)
- Memory: ~50 MB
- Disk I/O: Direct write from camera buffer
- Power: Minimal

**With OpenCV:**
- CPU: 40-60% (decoding + encoding both cameras)
- Memory: ~500 MB (frame buffers, codec state)
- Disk I/O: Write after re-encoding
- Power: 10-15W additional heat
- **Would cause thermal throttling on N100 mini PC**

### 6. Code Complexity

**FFmpeg Subprocess (Current Implementation):**
```python
cmd = [
    '/usr/lib/jellyfin-ffmpeg/ffmpeg',
    '-f', 'v4l2',
    '-input_format', 'h264',
    '-i', '/dev/video0',
    '-c:v', 'copy',
    '-f', 'segment',
    '-segment_time', '1800',
    'output_%03d.mp4'
]
subprocess.Popen(cmd)
```
Simple, clean, 10 lines.

**OpenCV Equivalent:**
```python
cap = cv2.VideoCapture('/dev/video0')
fourcc = cv2.VideoWriter_fourcc(*'H264')
out = cv2.VideoWriter('output.mp4', fourcc, 60, (2560, 1440))

segment_start = time.time()
frame_count = 0

while True:
    ret, frame = cap.read()
    if not ret:
        # Handle errors
        break
    
    # Check if need new segment
    if time.time() - segment_start > 1800:
        out.release()
        # Generate new filename
        # Open new VideoWriter
        # Handle errors
    
    out.write(frame)
    frame_count += 1
    
    # Monitor disk space
    # Check for errors
    # etc...
```
Complex, error-prone, 50+ lines minimum.

### 7. When Would OpenCV Make Sense?

OpenCV is the right tool when you need:

#### Computer Vision Tasks
```python
# Face detection
cascade = cv2.CascadeClassifier('haarcascade_frontalface_default.xml')
faces = cascade.detectMultiScale(frame)

# Object tracking
tracker = cv2.TrackerKCF_create()

# Motion detection
diff = cv2.absdiff(frame1, frame2)
```

#### Real-time Frame Processing
```python
# Add overlays
cv2.putText(frame, timestamp, (10, 30), ...)
cv2.rectangle(frame, bbox, (0, 255, 0), 2)

# Apply filters
blurred = cv2.GaussianBlur(frame, (5, 5), 0)
edges = cv2.Canny(frame, 100, 200)
```

#### Live Display
```python
cv2.imshow('Camera Feed', frame)
cv2.waitKey(1)
```

**But this project needs:**
- ✅ Long-running continuous recording (not CV analysis)
- ✅ Hardware-accelerated encoding (QSV)
- ✅ Minimal CPU/power usage (N100 is low-power)
- ✅ Segmented MP4 files (for easy management)
- ✅ Production reliability (24/7 uptime)

None of which require or benefit from OpenCV.

## Real-World Impact

### Scenario: Dual 1440p@60fps Recording for 24 hours

**With FFmpeg (Current):**
- CPU usage: <1%
- Power consumption: ~6W total system
- Temperature: 35-40°C
- Files: 48 × 2.5GB segments = 120GB total
- Quality: Bit-perfect from camera
- Uptime: 24/7 stable

**With OpenCV:**
- CPU usage: 40-60%
- Power consumption: ~20W total system
- Temperature: 60-70°C (thermal throttling risk)
- Files: 48 × 2.5GB segments = 120GB total (if no drops)
- Quality: Re-encoded (some loss)
- Uptime: Likely crashes from heat/memory

## Hybrid Approach (If Needed Later)

If you want computer vision **in addition to** recording:

### Option 1: Parallel Streams
```python
# FFmpeg records (efficient)
recorder = subprocess.Popen(['ffmpeg', '-i', '/dev/video0', '-c:v', 'copy', 'output.mp4'])

# OpenCV analyzes same camera (separate stream)
cap = cv2.VideoCapture('/dev/video0')
while True:
    ret, frame = cap.read()
    # Do CV analysis (detection, tracking, etc.)
    # Don't write frames - FFmpeg handles recording
```

### Option 2: Tee Output
```bash
# FFmpeg records AND pipes frames to Python
ffmpeg -i /dev/video0 \
  -c:v copy output.mp4 \                    # Efficient recording
  -f rawvideo -pix_fmt bgr24 - | \          # Pipe frames to stdout
  python3 analyze.py                         # CV analysis in Python
```

### Option 3: Analyze Recordings Post-Process
```python
# Record with FFmpeg (efficient, 24/7)
# Analyze recordings later (when needed)
for video_file in recordings:
    cap = cv2.VideoCapture(video_file)
    # Run CV analysis on saved files
```

## Conclusion

**FFmpeg is the correct choice because:**

1. ✅ **Primary goal is recording, not computer vision**
2. ✅ **Cameras output H.264 natively** → stream copy is optimal
3. ✅ **Intel QSV hardware** → FFmpeg has native support
4. ✅ **Low-power N100** → can't afford 40-60% CPU overhead
5. ✅ **24/7 reliability** → FFmpeg is proven for this use case
6. ✅ **Built-in segmentation** → no custom frame management needed

**OpenCV would only make sense if:**
- ❌ You needed real-time computer vision (face detection, tracking, etc.)
- ❌ You needed to modify frames before recording (overlays, filters)
- ❌ You needed live display with cv2.imshow()

**None of these apply to your use case.**

The Python rewrite uses FFmpeg via subprocess because it's **the right tool for the job**. The Python part adds value through:
- Configuration management (YAML)
- System validation and monitoring
- Storage cleanup automation
- Health checking and statistics
- Better error handling and logging

This is **sophisticated Python architecture around the right underlying tool**, not replacing the right tool with a worse one.

---

**TL;DR**: FFmpeg is for **recording**, OpenCV is for **computer vision**. You're doing recording with hardware acceleration, so FFmpeg is correct.
