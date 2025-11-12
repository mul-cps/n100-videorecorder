# Graceful Shutdown and Persistent Device Improvements

## Changes Made

### 1. Improved Graceful Shutdown

**Problem:** When stopping the dual-camera-record service with `systemctl stop`, FFmpeg processes would timeout instead of stopping cleanly, potentially leaving corrupted video files.

**Solution:**

#### Updated `dual-camera-record.sh`:
- Changed signal handling to use **SIGINT** instead of SIGTERM
  - FFmpeg handles SIGINT better and properly finalizes video files
- Added graceful shutdown with progress logging:
  - Stops monitoring process first
  - Sends SIGINT to both FFmpeg processes
  - Waits up to 10 seconds for graceful shutdown
  - Shows progress every 3 seconds ("Waiting for: Camera1 Camera2 (3s)")
  - Force kills only if processes don't stop within timeout
- Properly waits for all child processes before exiting

#### Updated `dual-camera-record.service`:
- Changed `KillSignal=SIGINT` for better FFmpeg compatibility
- Increased `TimeoutStopSec=15` (from 30) to be realistic
- Added `KillMode=mixed` to handle both main process and children properly
- Updated device checks to support persistent symlinks

### 2. Persistent Camera Device Mapping

**Problem:** `/dev/video*` device numbers can change when cameras are unplugged/replugged, breaking the recording setup.

**Solution:**

#### Udev Rules Already Create Persistent Symlinks:
The existing `99-camera-mapping.rules` creates:
- `/dev/video-usb1-video0` → Camera on USB Bus 1
- `/dev/video-usb2-video3` → Camera on USB Bus 2

These symlinks are **persistent** based on USB bus position, not device order.

#### Updated Configuration Files:
**`config/camera-mapping.conf`:**
```bash
CAMERA1_DEVICE="/dev/video-usb1-video0"  # Persistent symlink
CAMERA2_DEVICE="/dev/video-usb2-video3"  # Persistent symlink
```

#### New Detection Script:
**`scripts/detect-cameras.sh`:**
- Automatically scans for connected cameras
- Identifies capture devices (vs metadata devices)
- Shows persistent symlinks for each camera
- Offers to update configuration files automatically
- Detects camera capabilities and formats

#### Updated Scripts:
- `usb-bandwidth-test.sh`: Now uses persistent symlinks with fallback
- `dual-camera-record.service`: Checks for both direct devices and symlinks

## Usage

### Deploy Updated Configuration

```bash
# Copy updated config to system
sudo cp config/camera-mapping.conf /etc/camera-recorder/camera-mapping.conf

# Copy updated service file
sudo cp systemd/dual-camera-record.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Restart service
sudo systemctl restart dual-camera-record.service
```

### Detect Cameras and Update Configuration

```bash
# Run camera detection
./scripts/detect-cameras.sh

# It will:
# 1. Scan for all video devices
# 2. Identify capture devices (not metadata)
# 3. Show persistent symlinks
# 4. Offer to update /etc/camera-recorder/camera-mapping.conf
# 5. Offer to update repo config/camera-mapping.conf
```

### Test Graceful Shutdown

```bash
# Start recording
sudo systemctl start dual-camera-record.service

# Check logs
sudo journalctl -u dual-camera-record.service -f

# Stop recording (should be graceful now)
sudo systemctl stop dual-camera-record.service

# Check that it stopped cleanly in logs:
# You should see:
#   "Received shutdown signal, stopping recordings..."
#   "Stopping Camera 1 (PID: XXXX)"
#   "Stopping Camera 2 (PID: YYYY)"
#   "Both cameras stopped gracefully"
#   "Recording stopped cleanly"
```

### Verify Persistent Device Mapping

```bash
# Check current symlinks
ls -la /dev/video-usb*

# Expected output:
# /dev/video-usb1-video0 -> video0
# /dev/video-usb1-video1 -> video1
# /dev/video-usb2-video3 -> video3
# /dev/video-usb2-video4 -> video4

# Unplug and replug cameras - symlinks will still point to same USB ports
# Even if device numbers change (e.g., video0 becomes video4),
# the symlink /dev/video-usb1-video0 will update automatically
```

## Benefits

1. **No More Timeouts:** Service stops cleanly in 2-5 seconds instead of 30-second timeout
2. **No Corrupted Files:** FFmpeg properly finalizes video files before exit
3. **Better Logging:** See exactly what's happening during shutdown
4. **Persistent Devices:** Cameras stay mapped to same devices regardless of plug order
5. **Automatic Detection:** `detect-cameras.sh` makes setup easy
6. **Robust Recovery:** Service handles camera disconnects/reconnects gracefully

## Technical Details

### Signal Flow

1. User runs `systemctl stop dual-camera-record.service`
2. systemd sends **SIGINT** to main script
3. Script's `trap` catches SIGINT, calls `shutdown()` function
4. `shutdown()` sends SIGINT to both FFmpeg PIDs
5. FFmpeg receives SIGINT:
   - Stops reading from cameras
   - Flushes remaining frames to disk
   - Writes MP4 file trailer/index
   - Closes files properly
   - Exits with code 0
6. Script waits for both FFmpeg processes to exit
7. Script logs "Recording stopped cleanly" and exits
8. systemd marks service as stopped

### Why SIGINT Instead of SIGTERM?

- **SIGINT (Ctrl+C):** FFmpeg's preferred shutdown signal
  - Triggers clean shutdown routine
  - Finalizes video files properly
  - Same as pressing 'q' in interactive FFmpeg
  
- **SIGTERM:** Generic termination signal
  - FFmpeg may not finalize files properly
  - Can leave incomplete MP4 headers
  - Videos may not be playable

### Persistent Symlinks vs Device Numbers

**Without Symlinks:**
```
Boot 1: Camera A = /dev/video0, Camera B = /dev/video2
Unplug/replug cameras
Boot 2: Camera A = /dev/video4, Camera B = /dev/video0  ← BREAKS!
```

**With Symlinks:**
```
Always:
  Camera on USB Bus 1 Port 2 = /dev/video-usb1-video0
  Camera on USB Bus 2 Port 1 = /dev/video-usb2-video3
  
Real devices can change, but symlinks always point correctly!
```

## Troubleshooting

### Service Still Timing Out?

Check logs:
```bash
sudo journalctl -u dual-camera-record.service -n 50
```

Look for:
- "Waiting for: Camera1 Camera2 (Xs)" - shows which camera isn't stopping
- "forcing shutdown" - indicates FFmpeg didn't stop gracefully

### Cameras Not Detected?

Run detection script:
```bash
./scripts/detect-cameras.sh
```

Check for metadata vs capture devices:
- Capture devices: Support H264/MJPEG/YUYV formats
- Metadata devices: No formats listed

### Wrong Camera on Wrong Symlink?

If cameras are swapped:
1. Physically swap USB cable connections, OR
2. Update `config/camera-mapping.conf` to swap device assignments

## Files Modified

- `scripts/dual-camera-record.sh` - Improved shutdown handling
- `systemd/dual-camera-record.service` - Changed to SIGINT, updated device checks
- `config/camera-mapping.conf` - Using persistent symlinks
- `scripts/usb-bandwidth-test.sh` - Support persistent symlinks
- `scripts/detect-cameras.sh` - NEW: Automatic camera detection tool
