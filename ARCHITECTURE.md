# Camera Recorder Web Interface - Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Camera Recorder System                        │
│                         (Single Python Process)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐        │
│  │  Camera 1      │  │  Camera 2      │  │  Camera N      │        │
│  │  Recorder      │  │  Recorder      │  │  Recorder      │        │
│  │  (FFmpeg)      │  │  (FFmpeg)      │  │  (FFmpeg)      │        │
│  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘        │
│          │                   │                   │                  │
│          └───────────────────┴───────────────────┘                  │
│                              │                                       │
│                    ┌─────────▼──────────┐                           │
│                    │ MultiCameraRecorder │                           │
│                    └─────────┬──────────┘                           │
│                              │                                       │
│          ┌───────────────────┼───────────────────┐                  │
│          │                   │                   │                  │
│  ┌───────▼────────┐  ┌──────▼──────┐  ┌────────▼────────┐         │
│  │ Storage        │  │ Transcoder  │  │ Web Interface   │         │
│  │ Manager        │  │ (Background)│  │ (Flask)         │         │
│  └────────────────┘  └─────────────┘  └────────┬────────┘         │
│                                                  │                  │
│                                                  │                  │
└──────────────────────────────────────────────────┼──────────────────┘
                                                   │
                                                   │ HTTP :8080
                                                   │
                         ┌─────────────────────────┼─────────────────────────┐
                         │                         │                         │
                    ┌────▼─────┐           ┌──────▼──────┐          ┌───────▼───────┐
                    │ Browser  │           │  API Client │          │ Mobile Device │
                    │ (Desktop)│           │  (Script)   │          │   (Phone)     │
                    └──────────┘           └─────────────┘          └───────────────┘
```

## Component Details

### Camera Recorders (FFmpeg Processes)
- One FFmpeg process per camera
- Records H.264 video directly from camera
- Segments into 30-minute chunks
- Writes to `/storage/recordings/<camera_id>/`

### MultiCameraRecorder
- Manages all camera recorder instances
- Handles start/stop operations
- Monitors health of processes
- Provides statistics

### Storage Manager
- Monitors disk space
- Automatic cleanup of old recordings
- Emergency procedures for critical disk space
- Per-camera storage statistics

### Background Transcoder
- Converts H.264 → H.265 for space savings
- Runs during scheduled hours (e.g., 2 AM - 6 AM)
- Respects CPU and I/O limits
- Verifies quality before deleting originals

### Web Interface (Flask)
- Embedded HTTP server on port 8080
- Bootstrap 5 responsive UI
- REST API for all operations
- Auto-refresh every 30 seconds
- Runs in separate thread

## Data Flow

### Recording Flow
```
Camera → FFmpeg → Segmented MP4s → /storage/recordings/<camera_id>/
                                          ↓
                                    Transcoder (scheduled)
                                          ↓
                                    HEVC-encoded MP4s
                                          ↓
                                    Delete originals (after verification)
```

### Web Interface Flow
```
Browser → HTTP Request → Flask Routes → App Logic → Response
                                              ↓
                                        MultiCameraRecorder
                                        Storage Manager
                                        Transcoder
```

## API Endpoints

### Read Operations (GET)
- `/api/status` → System status
- `/api/cameras` → Camera list
- `/api/recordings` → Recordings list
- `/api/storage` → Disk usage
- `/api/system/cpu` → CPU usage
- `/api/system/memory` → Memory usage
- `/api/logs` → Recent logs
- `/api/transcoding/status` → Transcoding info

### Control Operations (POST)
- `/api/camera/<id>/start` → Start camera
- `/api/camera/<id>/stop` → Stop camera
- `/api/start_all` → Start all
- `/api/stop_all` → Stop all
- `/api/transcoding/enable` → Enable transcoding
- `/api/transcoding/disable` → Disable transcoding

### File Operations
- `/api/download/<cam>/<file>` → Download (GET)
- `/api/delete/<cam>/<file>` → Delete (DELETE)

## Process Model

```
Main Process (Python)
├── Main Thread (Recording Loop)
│   ├── Camera Health Checks
│   ├── Storage Monitoring
│   └── Periodic Cleanup
│
├── Transcoder Thread (if enabled)
│   ├── File Discovery
│   ├── FFmpeg Transcoding
│   └── Verification
│
└── Web Interface Thread
    ├── Flask HTTP Server
    ├── Request Handling
    └── API Processing

Subprocess: FFmpeg (Camera 1)
Subprocess: FFmpeg (Camera 2)
Subprocess: FFmpeg (Camera N)
```

## File Structure

```
/storage/recordings/
├── cam1/
│   ├── cam1_20231114_100000.mp4
│   ├── cam1_20231114_103000.mp4
│   └── cam1_20231114_110000.mp4
└── cam2/
    ├── cam2_20231114_100000.mp4
    ├── cam2_20231114_103000.mp4
    └── cam2_20231114_110000.mp4

/var/log/camera-recorder/
├── camera-recorder.log
├── cam1.log
└── cam2.log

/etc/camera-recorder/
└── config.yaml
```

## Configuration Hierarchy

```
config.yaml
├── cameras:
│   ├── cam1: { device, resolution, framerate, ... }
│   └── cam2: { device, resolution, framerate, ... }
├── encoding: { codec, quality, preset, ... }
├── recording: { segment_time, base_directory, ... }
├── storage: { cleanup_enabled, cleanup_days, ... }
├── transcoding: { enabled, schedule, codec, ... }
└── web: { port, host }
```

## Security Layers

```
┌─────────────────────────────────────┐
│  Internet / External Network        │
└──────────────┬──────────────────────┘
               │
     ┌─────────▼──────────┐
     │   Firewall (UFW)   │  ← Restrict port 8080
     └─────────┬──────────┘
               │
  ┌────────────▼───────────────┐
  │  Reverse Proxy (nginx)     │  ← HTTPS, Auth
  └────────────┬───────────────┘
               │
          ┌────▼─────┐
          │ Web App  │  ← localhost:8080
          │ (Flask)  │
          └──────────┘
```

## Performance Characteristics

| Component | CPU Usage | Memory | Disk I/O |
|-----------|-----------|--------|----------|
| FFmpeg (per camera) | 5-10% | 50-100 MB | High (write) |
| Transcoder | 10-15% | 100-200 MB | Very High |
| Web Interface | <1% | 20-30 MB | Minimal |
| Storage Manager | <1% | 10 MB | Low (read) |
| **Total System** | ~20-30% | ~500 MB | Variable |

## Integration Points

### With SystemD
```
camera-recorder-python.service
├── Starts main Python process
├── Auto-restart on failure
├── Logs to journald
└── Includes web interface automatically
```

### With Existing Scripts
- Camera detection: `camera-recorder --detect`
- Validation: `camera-recorder --validate`
- Statistics: `camera-recorder --stats`
- Cleanup: `camera-recorder --cleanup`

### With Monitoring Tools
- Prometheus: Export metrics via API
- Grafana: Visualize statistics
- Nagios/Zabbix: Health check endpoints
- Custom scripts: Use REST API

## Deployment Scenarios

### Local Development
```
config.yaml: web_host: "127.0.0.1"
Access: http://localhost:8080
Security: Local only
```

### Home Network
```
config.yaml: web_host: "0.0.0.0"
Firewall: Allow from 192.168.1.0/24
Access: http://192.168.1.x:8080
Security: Firewall rules
```

### Remote Access (VPN)
```
config.yaml: web_host: "127.0.0.1"
VPN: WireGuard/OpenVPN tunnel
Access: http://127.0.0.1:8080 via VPN
Security: VPN authentication
```

### Production (with Reverse Proxy)
```
config.yaml: web_host: "127.0.0.1"
nginx: HTTPS + Basic Auth
Access: https://cameras.example.com
Security: HTTPS + Authentication
```

---

This architecture provides:
- ✅ Single process (easy management)
- ✅ Low resource usage
- ✅ Integrated web interface
- ✅ Full remote control
- ✅ Scalable to many cameras
- ✅ Extensible via REST API
