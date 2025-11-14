# Web Interface Enhancements

## Overview
This document summarizes the sophisticated enhancements made to the camera recorder web interface for better monitoring, debugging, and failure recovery.

## 1. Enhanced Camera Health Monitoring

### Sophisticated Status Detection
- **Multi-level health checks**: Direct process checking via `recorder.is_alive()` instead of unreliable process search
- **Real-time health status**: Camera cards show actual recorder health, not just process existence
- **Process validation**: Double-checks that processes are alive and not zombie/crashed
- **Visual indicators**: Color-coded badges and border highlights for unhealthy cameras

### API Improvements (`/api/cameras`)
```python
{
    'id': 'cam1',
    'name': 'Primary Camera',
    'recording': true,
    'healthy': true,  // NEW: Health indicator
    ...
}
```

### Visual Indicators
- **Green "RECORDING" badge**: Healthy, active recording
- **Yellow "UNHEALTHY" badge**: Process exists but may have crashed
- **Gray "STOPPED" badge**: Intentionally stopped
- **Warning icon**: Shows on camera cards with health issues
- **Orange border**: Highlights unhealthy camera cards

## 2. Enhanced System Status

### Detailed Health Reporting (`/api/status`)
```json
{
    "cameras": {
        "total": 2,
        "recording": 1,
        "healthy": 1,
        "issues": 1
    },
    "health_status": "degraded",  // healthy | degraded | critical
    "processes": [
        {
            "pid": 12345,
            "cpu": 5.2,
            "memory": 1.5,
            "camera": "cam1"  // NEW: Identifies which camera
        }
    ]
}
```

### Dashboard Alerts
- **Automatic warnings**: Shows alerts when cameras are down
- **Health status badge**: Displays system health (Healthy/Degraded/Critical)
- **Issue counter**: Shows "X/Y cameras operational" when issues detected

## 3. Camera Restart Functionality

### New API Endpoint
`POST /api/system/restart_cameras`

Performs intelligent restart sequence:
1. Gracefully stops all cameras (10s timeout)
2. Waits 2 seconds for cleanup
3. Restarts all cameras
4. Reports success/failure for each camera

### Response Format
```json
{
    "success": true,
    "message": "All 2 cameras restarted successfully",
    "warning": "1 camera failed to start"  // Optional
}
```

### UI Button
- **Location**: Camera Controls section, alongside Start All / Stop All
- **Confirmation dialog**: Prevents accidental restarts
- **Progress feedback**: Shows status messages during restart
- **Auto-refresh**: Reloads camera status after restart

## 4. Transcoding Debug Enhancements

### Enhanced Candidate Scanning
Added detailed statistics logging:
```
Scanned 450 files: 12 candidates, 144 too new, 280 already transcoded, 0 in progress, 14 not H.264
```

### Improved Error Detection
- **ffprobe failures**: Explicitly logs when ffprobe is not found or fails
- **Codec detection**: Debug logs show codec for each file checked
- **Age filtering**: Logs cutoff time when scanning for candidates

### Better Logging
```python
logger.debug(f"{file_path.name}: codec={codec}")
logger.warning(f"ffprobe failed for {file_path.name}: {stderr}")
logger.error("ffprobe not found! Please install ffmpeg/ffprobe")
```

## 5. Log Formatting Enhancements

### Syntax Highlighting
- **Timestamps**: Gray, monospace font
- **Log levels**: Color-coded badges
  - ERROR/CRITICAL: Red
  - WARNING: Yellow
  - INFO: Cyan
  - DEBUG: Gray
- **Module names**: Italic gray text
- **Messages**: Clean, readable formatting

### Structured Display
```
2025-11-14 11:39:33,004  [INFO]  camera_recorder.transcoder  Force transcoding: finding candidates...
```

## 6. Transcoding Progress Display

### Real-time Progress Tracking
- **Progress bar**: Visual percentage indicator
- **File details**: Shows current file being transcoded
- **Size tracking**: Original size, current size, estimated savings
- **Camera identification**: Shows which camera the file is from

### Progress Data Structure
```json
{
    "filename": "cam1_20251112_115004.mp4",
    "camera": "cam1",
    "original_size_mb": 14.8,
    "transcoding_size_mb": 7.2,
    "progress_percent": 48,
    "estimated_savings_mb": 7.6
}
```

## Usage Guide

### Monitoring Camera Health
1. **Check dashboard**: Green badges = healthy, yellow = issues
2. **System status**: Shows health summary (X/Y cameras operational)
3. **Auto-alerts**: Red banner appears when cameras crash

### Handling Camera Failures
1. **Identify issue**: Look for yellow "UNHEALTHY" badges or orange borders
2. **Try restart**: Click "Restart All" button in Camera Controls
3. **Confirm action**: Click OK in confirmation dialog
4. **Wait**: System stops and restarts all cameras (takes ~12 seconds)
5. **Verify**: Check that cameras show green "RECORDING" status

### Debugging Transcoding
1. **Check logs**: Look for ffprobe errors or codec detection issues
2. **Force transcode**: Click "Transcode Now" to test immediately
3. **Monitor progress**: Watch the progress bar and file details
4. **Review stats**: Check scanned files breakdown for issues

## Technical Implementation

### Camera Status Flow
```
1. Web Interface calls app.recorder.check_health()
2. Recorder checks each camera's is_alive() status
3. is_alive() validates process.poll() is None
4. Additional validation checks process responsiveness
5. Status returned to API with healthy flag
6. Dashboard renders appropriate badges and borders
```

### Restart Sequence
```
1. User clicks "Restart All" button
2. Confirmation dialog shown
3. POST /api/system/restart_cameras
4. Backend stops all cameras (timeout: 10s)
5. Sleep 2s for cleanup
6. Start all cameras
7. Return success/failure counts
8. Frontend shows alerts and refreshes
```

### Transcoding Debug Flow
```
1. _find_candidates() scans recordings directory
2. For each file: check age, transcoded marker, H.264 codec
3. Log detailed stats: too_new, already_transcoded, not_h264
4. ffprobe errors caught and logged explicitly
5. Return candidate list with full statistics
```

## Benefits

### For Operators
- **Instant visibility**: See camera health at a glance
- **Quick recovery**: One-click restart for all cameras
- **Better diagnostics**: Detailed logs and progress tracking
- **Proactive alerts**: Automatic warnings for issues

### For Developers
- **Better debugging**: Detailed transcoding logs
- **Error tracking**: ffprobe failures logged explicitly
- **Health monitoring**: Sophisticated process validation
- **Progress visibility**: Real-time transcoding status

## Future Enhancements

### Potential Improvements
1. **Individual camera restart**: Restart single camera instead of all
2. **Health history**: Track camera uptime and crash frequency
3. **Auto-recovery**: Automatic restart on camera crash detection
4. **Email alerts**: Notify on camera failures
5. **Resource monitoring**: Show per-camera CPU/memory usage
6. **Log filtering**: Filter logs by level or module
7. **Transcoding scheduler**: Web UI for schedule configuration

## Troubleshooting

### Camera Shows "UNHEALTHY"
- Check system logs: `journalctl -u camera-recorder-python -f`
- Look for "Camera X recorder died!" messages
- Try restart using "Restart All" button
- Check USB connections and device permissions

### Transcoding Shows "No files found"
- Check logs for ffprobe errors
- Verify files are H.264: `ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 /path/to/file.mp4`
- Ensure files meet age requirement (min_age_days: 2)
- Check for .transcoded marker files

### Restart Button Not Working
- Check browser console for JavaScript errors
- Verify API endpoint is accessible: `curl -X POST http://localhost:8080/api/system/restart_cameras`
- Check service logs for restart errors
- Ensure user has permissions to start/stop recorders
