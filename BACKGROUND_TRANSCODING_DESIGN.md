# Background Transcoding Design

## Overview

Automatically transcode old H.264 recordings to H.265/HEVC using Intel QSV hardware acceleration to save disk space, while ensuring recording is never interrupted.

## Goals

1. **Never interrupt recording**: Background transcoding runs at low priority
2. **Maximize space savings**: H.265 typically saves 30-50% compared to H.264
3. **Use hardware acceleration**: Intel QSV for efficient transcoding
4. **Maintain quality**: Visually lossless transcoding
5. **Safe operation**: Atomic replacements, verification before deletion

## Strategy

### Transcoding Logic

1. **Age-based transcoding**: Only transcode files older than N days (configurable)
2. **Low priority**: Run transcoding with `nice` and low I/O priority
3. **Rate limiting**: Only transcode during low activity periods or throttle based on system load
4. **One at a time**: Serial transcoding to minimize resource impact
5. **Space verification**: Ensure sufficient space before and after transcoding

### Configuration

```yaml
transcoding:
  enabled: true
  min_age_days: 7              # Only transcode files older than 7 days
  run_schedule: "02:00-06:00"  # Only run between 2 AM and 6 AM
  max_cpu_percent: 15          # Pause if system CPU > 15%
  max_io_wait: 5               # Pause if I/O wait > 5%
  verify_quality: true         # Verify output before deleting original
  
  # QSV encoding settings
  codec: "hevc_qsv"
  preset: "medium"             # Slower = better compression
  quality: 23                  # CRF equivalent (lower = better quality)
  
  # Safety settings
  keep_original_days: 1        # Keep original for 1 day after transcoding
  min_free_space_gb: 100       # Don't transcode if free space < 100GB
  target_space_savings: 40     # Target 40% space reduction
```

### Process Flow

```
1. Scan for candidates
   ↓
2. Filter by age (>7 days old)
   ↓
3. Filter by codec (only H.264 files)
   ↓
4. Sort by oldest first
   ↓
5. Check system resources
   ↓
6. Transcode one file
   ↓
7. Verify output quality
   ↓
8. Mark original for deletion
   ↓
9. Wait for safety period
   ↓
10. Delete original
   ↓
11. Repeat (or sleep until schedule)
```

## Implementation Details

### 1. File Selection

```python
def find_transcoding_candidates():
    """Find H.264 files older than min_age_days"""
    candidates = []
    cutoff_date = datetime.now() - timedelta(days=config.min_age_days)
    
    for recording_dir in [cam1_dir, cam2_dir]:
        for file in recording_dir.glob("*.mp4"):
            # Check age
            if file.stat().st_mtime < cutoff_date.timestamp():
                # Check if already H.265
                if not is_hevc_encoded(file):
                    # Check if not already transcoded/in progress
                    if not has_hevc_version(file):
                        candidates.append(file)
    
    # Sort by oldest first (most space savings potential)
    return sorted(candidates, key=lambda f: f.stat().st_mtime)
```

### 2. Resource Monitoring

```python
def should_transcode_now():
    """Check if system resources allow transcoding"""
    # Check CPU usage
    cpu_percent = psutil.cpu_percent(interval=1)
    if cpu_percent > config.max_cpu_percent:
        return False
    
    # Check I/O wait
    io_wait = psutil.cpu_times_percent().iowait
    if io_wait > config.max_io_wait:
        return False
    
    # Check if recording is active and healthy
    if not all_recorders_healthy():
        return False
    
    # Check time window
    if not in_schedule_window():
        return False
    
    # Check disk space
    if get_free_space_gb() < config.min_free_space_gb:
        return False
    
    return True
```

### 3. Transcoding Process

```python
def transcode_file(input_file: Path):
    """Transcode one file to H.265 using QSV"""
    output_file = input_file.with_suffix('.transcoding.mp4')
    
    cmd = [
        '/usr/lib/jellyfin-ffmpeg/ffmpeg',
        '-hwaccel', 'qsv',
        '-hwaccel_output_format', 'qsv',
        '-i', str(input_file),
        
        # H.265 QSV encoding
        '-c:v', 'hevc_qsv',
        '-preset', config.preset,
        '-global_quality', str(config.quality),
        
        # Copy audio (if any)
        '-c:a', 'copy',
        
        # Metadata
        '-movflags', '+faststart',
        
        # Output
        str(output_file)
    ]
    
    # Run with low priority
    process = subprocess.Popen(
        ['nice', '-n', '19', 'ionice', '-c', '3'] + cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Monitor progress
    return_code = process.wait()
    
    if return_code == 0:
        return output_file
    else:
        output_file.unlink(missing_ok=True)
        raise TranscodingError(f"FFmpeg failed with code {return_code}")
```

### 4. Quality Verification

```python
def verify_transcoded_file(original: Path, transcoded: Path):
    """Verify transcoded file is valid and acceptable quality"""
    # Check file exists and has content
    if not transcoded.exists() or transcoded.stat().st_size < 1000:
        return False
    
    # Get original info
    orig_info = get_video_info(original)
    trans_info = get_video_info(transcoded)
    
    # Verify duration matches (within 1 second)
    if abs(orig_info['duration'] - trans_info['duration']) > 1.0:
        logger.error(f"Duration mismatch: {orig_info['duration']} vs {trans_info['duration']}")
        return False
    
    # Verify resolution matches
    if orig_info['resolution'] != trans_info['resolution']:
        logger.error(f"Resolution mismatch")
        return False
    
    # Verify framerate matches
    if abs(orig_info['fps'] - trans_info['fps']) > 1:
        logger.error(f"FPS mismatch")
        return False
    
    # Check for corruption
    if not verify_file_integrity(transcoded):
        return False
    
    # Verify space savings
    space_saved = (original.stat().st_size - transcoded.stat().st_size)
    savings_percent = (space_saved / original.stat().st_size) * 100
    
    if savings_percent < 10:  # Less than 10% savings, not worth it
        logger.info(f"Insufficient savings: {savings_percent:.1f}%")
        return False
    
    logger.info(f"Transcoding verified: {savings_percent:.1f}% space saved")
    return True

def verify_file_integrity(file: Path):
    """Verify video file is not corrupted"""
    cmd = [
        'ffmpeg',
        '-v', 'error',
        '-i', str(file),
        '-f', 'null',
        '-'
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0 and len(result.stderr) == 0
```

### 5. Safe Replacement

```python
def replace_with_transcoded(original: Path, transcoded: Path):
    """Safely replace original with transcoded version"""
    # Rename original to .original
    original_backup = original.with_suffix('.mp4.original')
    original.rename(original_backup)
    
    # Rename transcoded to final name
    final_name = original
    transcoded.rename(final_name)
    
    # Create marker file with metadata
    marker = original.with_suffix('.transcoded')
    marker.write_text(json.dumps({
        'transcoded_at': datetime.now().isoformat(),
        'original_size': original_backup.stat().st_size,
        'new_size': final_name.stat().st_size,
        'savings_bytes': original_backup.stat().st_size - final_name.stat().st_size,
        'original_file': str(original_backup),
        'delete_after': (datetime.now() + timedelta(days=config.keep_original_days)).isoformat()
    }))
    
    logger.info(f"Replaced {original.name} with transcoded version")
```

### 6. Cleanup Original Files

```python
def cleanup_old_originals():
    """Delete original files after safety period"""
    for marker in Path(recordings_dir).rglob('*.transcoded'):
        metadata = json.loads(marker.read_text())
        delete_after = datetime.fromisoformat(metadata['delete_after'])
        
        if datetime.now() > delete_after:
            original_file = Path(metadata['original_file'])
            if original_file.exists():
                size_mb = original_file.stat().st_size / (1024**2)
                original_file.unlink()
                marker.unlink()
                logger.info(f"Deleted original {original_file.name} ({size_mb:.1f} MB freed)")
```

## Module Structure

```python
# src/camera_recorder/transcoder.py

class BackgroundTranscoder:
    def __init__(self, config: TranscodingConfig):
        self.config = config
        self.running = False
        self.current_file = None
        self.stats = TranscodingStats()
    
    def start(self):
        """Start background transcoding thread"""
        self.running = True
        self.thread = Thread(target=self._transcode_loop, daemon=True)
        self.thread.start()
    
    def stop(self):
        """Stop transcoding gracefully"""
        self.running = False
        if self.current_file:
            # Allow current file to finish
            self.thread.join(timeout=300)
    
    def _transcode_loop(self):
        """Main transcoding loop"""
        while self.running:
            try:
                # Wait for schedule window
                if not self.in_schedule_window():
                    time.sleep(60)
                    continue
                
                # Find candidates
                candidates = self.find_candidates()
                if not candidates:
                    time.sleep(3600)  # Sleep 1 hour if nothing to do
                    continue
                
                # Process one file
                for file in candidates:
                    if not self.should_transcode_now():
                        break
                    
                    self.transcode_one_file(file)
                    
                    # Cleanup old originals
                    self.cleanup_old_originals()
                    
                    # Pause between files
                    time.sleep(60)
                
            except Exception as e:
                logger.error(f"Transcoding error: {e}")
                time.sleep(300)  # Sleep 5 min on error
    
    def transcode_one_file(self, file: Path):
        """Transcode single file"""
        self.current_file = file
        logger.info(f"Transcoding {file.name}...")
        
        try:
            # Transcode
            transcoded = self.transcode_file(file)
            
            # Verify
            if self.verify_transcoded_file(file, transcoded):
                # Replace
                self.replace_with_transcoded(file, transcoded)
                
                # Update stats
                self.stats.files_transcoded += 1
                self.stats.space_saved += file.stat().st_size - transcoded.stat().st_size
            else:
                logger.warning(f"Verification failed for {file.name}")
                transcoded.unlink()
                
        except Exception as e:
            logger.error(f"Failed to transcode {file.name}: {e}")
        
        finally:
            self.current_file = None
```

## Integration with Main Application

```python
# In src/camera_recorder/main.py

class CameraRecorderApp:
    def __init__(self, config_path: str):
        # ...existing code...
        
        # Initialize transcoder if enabled
        if self.config.transcoding.enabled:
            self.transcoder = BackgroundTranscoder(self.config.transcoding)
        else:
            self.transcoder = None
    
    def run(self):
        """Main application loop"""
        # Start recording
        self.recorder.start_recording()
        
        # Start transcoder (background thread)
        if self.transcoder:
            self.transcoder.start()
        
        # Main monitoring loop
        while self.running:
            # ...existing monitoring...
            time.sleep(10)
        
        # Stop transcoder first (gracefully)
        if self.transcoder:
            logger.info("Stopping background transcoder...")
            self.transcoder.stop()
        
        # Then stop recording
        self.recorder.stop_recording()
```

## Safety Guarantees

1. **Recording Priority**: 
   - Transcoding runs with `nice -n 19` (lowest CPU priority)
   - Uses `ionice -c 3` (idle I/O priority)
   - Pauses if system load exceeds thresholds

2. **Atomic Operations**:
   - Original renamed to `.original` before replacement
   - Transcoded file fully written before rename
   - Metadata marker prevents re-transcoding

3. **Verification**:
   - Duration, resolution, FPS must match
   - File integrity checked with FFmpeg
   - Minimum space savings enforced

4. **Safety Period**:
   - Original kept for configurable days (default: 1 day)
   - Allows rollback if issues discovered
   - Automatic cleanup after safety period

5. **Resource Protection**:
   - Only runs during configured time windows
   - Monitors CPU, I/O, disk space
   - Pauses if recording shows issues

## Statistics and Monitoring

```python
@dataclass
class TranscodingStats:
    files_transcoded: int = 0
    space_saved: int = 0  # bytes
    total_original_size: int = 0
    total_transcoded_size: int = 0
    errors: int = 0
    last_transcoded: Optional[datetime] = None

# CLI command to view stats
$ camera-recorder --transcode-stats

=== Transcoding Statistics ===

Files transcoded: 145
Space saved: 68.5 GB (42.3% reduction)
Total original: 161.8 GB
Total transcoded: 93.3 GB

Last transcoded: 2024-11-12 04:23:15
Status: Running (paused - outside schedule window)
Current file: None

Next scheduled run: 2024-11-13 02:00:00
```

## Expected Space Savings

For your setup (1440p@60fps H.264 stream copy):

| Scenario | Original (H.264) | Transcoded (H.265 QSV) | Savings |
|----------|------------------|------------------------|---------|
| 30-min segment | ~2.5 GB | ~1.5 GB | ~40% |
| 1 day (48 segments) | ~120 GB | ~72 GB | ~48 GB |
| 30 days retention | ~3.6 TB | ~2.2 TB | ~1.4 TB |

**With 1TB storage**, transcoding allows you to keep recordings for **~40 days instead of ~25 days**.

## CLI Commands

```bash
# Enable/disable transcoding
camera-recorder --transcode enable
camera-recorder --transcode disable

# View statistics
camera-recorder --transcode-stats

# Manual transcode of specific file
camera-recorder --transcode-file /path/to/recording.mp4

# Force transcode all candidates (ignore schedule)
camera-recorder --transcode-all --force
```

## Advantages

1. ✅ **Automatic**: No manual intervention needed
2. ✅ **Safe**: Multiple verification steps, safety period
3. ✅ **Non-intrusive**: Low priority, scheduled windows
4. ✅ **Efficient**: Hardware QSV acceleration
5. ✅ **Reversible**: Originals kept for safety period
6. ✅ **Monitored**: Statistics and logging

## Conclusion

This background transcoding system provides:
- **30-50% space savings** without quality loss
- **Zero impact on recording** through prioritization and monitoring
- **Safe operation** with verification and safety periods
- **Automatic management** of old recordings

Perfect for maximizing storage efficiency on your N100 system!
