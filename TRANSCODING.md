# Automated HEVC Transcoding System

## Overview

This system automatically converts older H.264 recordings to HEVC to save disk space while maintaining quality.

## How It Works

1. **Recording Phase** (Real-time)
   - Cameras record in H.264 (stream copy mode)
   - Fast, no CPU overhead, no frame drops
   - Files: ~36 MB per minute per camera

2. **Transcoding Phase** (Daily at 2 AM)
   - Files older than 2 days are converted to HEVC
   - Uses Intel QSV hardware acceleration
   - Saves ~50% disk space
   - Original files are replaced with HEVC versions

## Installation

```bash
# Run the setup script
chmod +x scripts/setup-transcoding.sh
./scripts/setup-transcoding.sh
```

## Storage Calculation

### Without Transcoding (H.264 only):
- **4.8 Mbps per camera** (actual measured bitrate)
- **9.6 Mbps total** for both cameras
- **104 GB per day**
- **~8.5 days** on 888 GB disk

### With Automated Transcoding:
- **Days 1-2:** H.264 (fast recording)
- **Day 3+:** HEVC (50% smaller)

**Effective storage:**
- Day 1-2: 104 GB × 2 = 208 GB (H.264)
- Day 3-30: 52 GB × 28 = 1,456 GB (HEVC)
- **Total for 30 days: ~1,664 GB**

**Your 888 GB disk can now hold:**
- 2 days H.264 + ~13 days HEVC
- **~15 days total** (almost double!)

## Configuration

Edit `/etc/systemd/system/transcode-recordings.service`:

```ini
Environment="TRANSCODE_AGE_DAYS=2"      # How old before transcoding
Environment="ENCODING_QUALITY=23"        # HEVC quality (18-28, lower=better)
Environment="ENCODING_PRESET=medium"     # fast, medium, slow
```

After changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart transcode-recordings.timer
```

## Usage

### Check Status
```bash
# Check if timer is active
systemctl status transcode-recordings.timer

# Check last transcoding job
systemctl status transcode-recordings.service

# View transcoding logs
journalctl -u transcode-recordings.service
```

### Manual Operation
```bash
# Run transcoding now (instead of waiting for 2 AM)
sudo systemctl start transcode-recordings.service

# Follow transcoding progress
sudo journalctl -u transcode-recordings.service -f

# Disable automatic transcoding
sudo systemctl disable transcode-recordings.timer

# Re-enable automatic transcoding
sudo systemctl enable transcode-recordings.timer
```

### Test First Run
```bash
# Do a test run to see how it works
sudo systemctl start transcode-recordings.service

# Watch progress
sudo journalctl -u transcode-recordings.service -f
```

## Monitoring

### Check transcoding statistics:
```bash
# View transcoding stats
cat /var/log/camera-recorder/transcode-stats.csv

# Format: original_size_mb, new_size_mb, savings_percent, duration_seconds
```

### Check logs:
```bash
# List all transcoding logs
ls -lh /var/log/camera-recorder/transcode-*.log

# View latest log
tail -f /var/log/camera-recorder/transcode-*.log | tail -1
```

## Scheduling

The default schedule is **daily at 2 AM**. To change:

Edit `/etc/systemd/system/transcode-recordings.timer`:

```ini
[Timer]
# Run every 6 hours
OnCalendar=00/6:00

# Or run twice daily (2 AM and 2 PM)
OnCalendar=02:00
OnCalendar=14:00
```

Then reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart transcode-recordings.timer
```

## Performance

- **CPU Usage:** 50% limit (runs at low priority, won't affect live recording)
- **Transcoding Speed:** ~2-3x real-time on Intel N100
  - 60-second video transcodes in ~20-30 seconds
- **Quality:** Minimal loss (HEVC Q23 ≈ H.264 original quality)

## Disk Space Projections

| Retention | H.264 Only | With HEVC Transcoding |
|-----------|------------|----------------------|
| 7 days | 726 GB | 416 GB |
| 14 days | 1,452 GB | 780 GB |
| **15 days** | **1,556 GB** | **~888 GB** ✓ |
| 30 days | 3,111 GB | 1,664 GB |

**Conclusion:** With automated transcoding, you can keep **~15 days** of recordings on your 888 GB disk!

## Troubleshooting

### Check if transcoding is working:
```bash
# Find HEVC files
find /storage/recordings -name "*.mp4" -exec ffprobe -v quiet -show_entries stream=codec_name {} \; | grep hevc

# Count H.264 vs HEVC files
echo "H.264 files:"
find /storage/recordings -name "*.mp4" -exec sh -c 'ffprobe "$1" 2>&1 | grep -q "Video: h264" && echo "$1"' _ {} \; | wc -l

echo "HEVC files:"
find /storage/recordings -name "*.mp4" -exec sh -c 'ffprobe "$1" 2>&1 | grep -q "Video: hevc" && echo "$1"' _ {} \; | wc -l
```

### If transcoding fails:
```bash
# Check QSV is available
/usr/lib/jellyfin-ffmpeg/ffmpeg -hwaccels | grep qsv

# Check permissions
ls -la /dev/dri/renderD128

# Run manually with debug
sudo -u bjoern /usr/local/bin/transcode-old-recordings.sh
```

## Files

- Script: `/usr/local/bin/transcode-old-recordings.sh`
- Service: `/etc/systemd/system/transcode-recordings.service`
- Timer: `/etc/systemd/system/transcode-recordings.timer`
- Logs: `/var/log/camera-recorder/transcode-*.log`
- Stats: `/var/log/camera-recorder/transcode-stats.csv`

## Uninstall

```bash
# Disable and remove
sudo systemctl stop transcode-recordings.timer
sudo systemctl disable transcode-recordings.timer
sudo rm /etc/systemd/system/transcode-recordings.{service,timer}
sudo rm /usr/local/bin/transcode-old-recordings.sh
sudo systemctl daemon-reload
```
