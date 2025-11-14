"""
Background transcoder for converting old H.264 recordings to H.265/HEVC.

This module provides automatic background transcoding of old recordings to save
disk space using Intel QSV hardware acceleration, while ensuring recording is
never interrupted.
"""

import os
import json
import subprocess
import logging
import time
from pathlib import Path
from datetime import datetime, timedelta
from threading import Thread, Event
from typing import List, Optional, Dict
from dataclasses import dataclass, asdict
from queue import Queue
import psutil

from .config import TranscodingConfig

logger = logging.getLogger(__name__)


@dataclass
class TranscodingStats:
    """Statistics for transcoding operations."""
    files_transcoded: int = 0
    files_failed: int = 0
    space_saved_bytes: int = 0
    total_original_bytes: int = 0
    total_transcoded_bytes: int = 0
    last_transcoded: Optional[str] = None
    last_error: Optional[str] = None
    
    def to_dict(self) -> Dict:
        """Convert to dictionary."""
        return asdict(self)
    
    @property
    def space_saved_gb(self) -> float:
        """Space saved in GB."""
        return self.space_saved_bytes / (1024**3)
    
    @property
    def savings_percent(self) -> float:
        """Percentage of space saved."""
        if self.total_original_bytes == 0:
            return 0.0
        return (self.space_saved_bytes / self.total_original_bytes) * 100


class BackgroundTranscoder:
    """Manages background transcoding of recordings."""
    
    def __init__(self, config: TranscodingConfig, recordings_base: Path):
        self.config = config
        self.recordings_base = Path(recordings_base)
        self.running = Event()
        self.thread: Optional[Thread] = None
        self.current_file: Optional[Path] = None
        self.stats = TranscodingStats()
        self.force_queue: Queue = Queue()  # Queue for force transcode requests
        self.total_queued = 0  # Track total files queued for better status reporting
        self._load_stats()
    
    def start(self):
        """Start background transcoding thread."""
        if not self.config.enabled:
            logger.info("Background transcoding disabled in config")
            return
        
        if self.running.is_set():
            logger.warning("Transcoder already running")
            return
        
        logger.info("Starting background transcoder")
        self.running.set()
        self.thread = Thread(target=self._transcode_loop, daemon=True, name="Transcoder")
        self.thread.start()
    
    def stop(self, timeout: int = 300):
        """Stop background transcoding gracefully."""
        if not self.running.is_set():
            return
        
        logger.info("Stopping background transcoder...")
        self.running.clear()
        
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=timeout)
            if self.thread.is_alive():
                logger.warning("Transcoder thread did not stop gracefully")
        
        self._save_stats()
        logger.info("Background transcoder stopped")
    
    def _transcode_loop(self):
        """Main transcoding loop."""
        while self.running.is_set():
            try:
                # Check if there's a force transcode request in the queue
                if not self.force_queue.empty():
                    candidates = self.force_queue.get()
                    
                    for file_path in candidates:
                        if not self.running.is_set():
                            break
                        
                        try:
                            self._transcode_one_file(file_path)
                            self.total_queued = max(0, self.total_queued - 1)
                        except Exception as e:
                            logger.error(f"Error transcoding {file_path.name}: {e}")
                            self.total_queued = max(0, self.total_queued - 1)
                        
                        # Small pause between files
                        time.sleep(5)
                    
                    self.force_queue.task_done()
                    continue
                
                # Check if we're in schedule window
                if not self._in_schedule_window():
                    logger.debug("Outside schedule window, sleeping...")
                    time.sleep(300)  # Check every 5 minutes
                    continue
                
                # Find transcoding candidates
                candidates = self._find_candidates()
                if not candidates:
                    logger.debug("No transcoding candidates found")
                    time.sleep(3600)  # Sleep 1 hour
                    continue
                
                logger.info(f"Found {len(candidates)} transcoding candidates")
                
                # Process files
                for file_path in candidates:
                    if not self.running.is_set():
                        break
                    
                    # Check system resources
                    if not self._should_transcode_now():
                        logger.info("System resources not suitable, pausing...")
                        time.sleep(300)
                        continue
                    
                    # Transcode one file
                    self._transcode_one_file(file_path)
                    
                    # Cleanup old originals
                    self._cleanup_old_originals()
                    
                    # Save stats
                    self._save_stats()
                    
                    # Pause between files
                    time.sleep(60)
                
            except Exception as e:
                logger.error(f"Error in transcoding loop: {e}", exc_info=True)
                self.stats.last_error = str(e)
                time.sleep(300)  # Sleep 5 min on error
    
    def _find_candidates(self, ignore_age: bool = False) -> List[Path]:
        """Find files eligible for transcoding."""
        candidates = []
        skipped_stats = {
            'too_new': 0,
            'already_transcoded': 0,
            'in_progress': 0,
            'not_h264': 0,
            'checked': 0
        }
        
        # Calculate cutoff time (ignore if force transcoding)
        if ignore_age:
            cutoff_time = 0  # All files eligible
        else:
            cutoff_time = time.time() - (self.config.min_age_days * 86400)
        
        logger.debug(f"Finding candidates (ignore_age={ignore_age}, cutoff_time={cutoff_time})")
        
        # Scan all camera directories
        for cam_dir in self.recordings_base.iterdir():
            if not cam_dir.is_dir():
                continue
            
            for video_file in cam_dir.glob("*.mp4"):
                skipped_stats['checked'] += 1
                
                # Skip if too new (unless ignoring age)
                if not ignore_age and video_file.stat().st_mtime > cutoff_time:
                    skipped_stats['too_new'] += 1
                    continue
                
                # Skip if already transcoded
                if self._is_transcoded(video_file):
                    skipped_stats['already_transcoded'] += 1
                    continue
                
                # Skip if transcoding in progress
                if video_file.with_suffix('.mp4.transcoding').exists():
                    skipped_stats['in_progress'] += 1
                    continue
                
                # Check if it's H.264 (not already H.265)
                if not self._is_h264(video_file):
                    skipped_stats['not_h264'] += 1
                    continue
                
                candidates.append(video_file)
        
        # Log statistics
        logger.info(f"Scanned {skipped_stats['checked']} files: "
                   f"{len(candidates)} candidates, "
                   f"{skipped_stats['too_new']} too new, "
                   f"{skipped_stats['already_transcoded']} already transcoded, "
                   f"{skipped_stats['in_progress']} in progress, "
                   f"{skipped_stats['not_h264']} not H.264")
        
        # Sort by oldest first
        candidates.sort(key=lambda f: f.stat().st_mtime)
        
        return candidates
    
    def _is_h264(self, file_path: Path) -> bool:
        """Check if file is H.264 encoded."""
        try:
            cmd = [
                'ffprobe',
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream=codec_name',
                '-of', 'default=noprint_wrappers=1:nokey=1',
                str(file_path)
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                logger.warning(f"ffprobe failed for {file_path.name}: {result.stderr}")
                return False
                
            codec = result.stdout.strip().lower()
            logger.debug(f"{file_path.name}: codec={codec}")
            return codec in ['h264', 'avc']
        except FileNotFoundError:
            logger.error("ffprobe not found! Please install ffmpeg/ffprobe")
            return False
        except Exception as e:
            logger.error(f"Error checking codec for {file_path}: {e}")
            return False
    
    def _is_transcoded(self, file_path: Path) -> bool:
        """Check if file has been transcoded."""
        # Quick check: if filename contains .hevc., it's already transcoded
        if '.hevc.' in file_path.name:
            return True
        # Otherwise check for marker file
        marker = file_path.with_suffix('.mp4.transcoded')
        return marker.exists()
    
    def _in_schedule_window(self) -> bool:
        """Check if current time is within transcoding schedule."""
        now = datetime.now()
        current_time = now.time()
        
        # Parse schedule times
        start_hour, start_min = map(int, self.config.run_schedule_start.split(':'))
        end_hour, end_min = map(int, self.config.run_schedule_end.split(':'))
        
        from datetime import time as time_class
        start_time = time_class(start_hour, start_min)
        end_time = time_class(end_hour, end_min)
        
        # Handle overnight schedules (e.g., 22:00 - 06:00)
        if start_time <= end_time:
            return start_time <= current_time <= end_time
        else:
            return current_time >= start_time or current_time <= end_time
    
    def _should_transcode_now(self) -> bool:
        """Check if system resources allow transcoding."""
        try:
            # Check CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            if cpu_percent > self.config.max_cpu_percent:
                logger.debug(f"CPU too high: {cpu_percent:.1f}%")
                return False
            
            # Check I/O wait (if available)
            try:
                io_wait = psutil.cpu_times_percent(interval=1).iowait
                if io_wait and io_wait > self.config.max_io_wait:
                    logger.debug(f"I/O wait too high: {io_wait:.1f}%")
                    return False
            except AttributeError:
                # iowait not available on all platforms
                pass
            
            # Check disk space
            disk = psutil.disk_usage(str(self.recordings_base))
            free_gb = disk.free / (1024**3)
            if free_gb < self.config.min_free_space_gb:
                logger.debug(f"Insufficient free space: {free_gb:.1f} GB")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error checking system resources: {e}")
            return False
    
    def _transcode_one_file(self, file_path: Path):
        """Transcode a single file."""
        self.current_file = file_path
        logger.info(f"Transcoding {file_path.name}...")
        
        temp_output = file_path.with_suffix('.mp4.transcoding')
        
        try:
            # Build FFmpeg command
            cmd = self._build_ffmpeg_command(file_path, temp_output)
            
            # Run with low priority
            start_time = time.time()
            process = subprocess.Popen(
                ['nice', '-n', '19', 'ionice', '-c', '3'] + cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Wait for completion
            stdout, stderr = process.communicate()
            elapsed = time.time() - start_time
            
            if process.returncode != 0:
                raise Exception(f"FFmpeg failed: {stderr.decode()}")
            
            logger.info(f"Transcoding completed in {elapsed:.1f}s")
            
            # Verify output
            if self.config.verify_quality:
                if not self._verify_transcoded_file(file_path, temp_output):
                    raise Exception("Verification failed")
            
            # Replace original with transcoded
            self._replace_with_transcoded(file_path, temp_output)
            
            # Update stats
            self.stats.files_transcoded += 1
            self.stats.last_transcoded = datetime.now().isoformat()
            
        except Exception as e:
            logger.error(f"Failed to transcode {file_path.name}: {e}")
            self.stats.files_failed += 1
            self.stats.last_error = str(e)
            
            # Cleanup temp file
            if temp_output.exists():
                temp_output.unlink()
        
        finally:
            self.current_file = None
    
    def _build_ffmpeg_command(self, input_file: Path, output_file: Path) -> List[str]:
        """Build FFmpeg command for transcoding."""
        return [
            'ffmpeg',
            '-hwaccel', 'vaapi',
            '-hwaccel_device', '/dev/dri/renderD128',
            '-hwaccel_output_format', 'vaapi',
            '-i', str(input_file),
            
            # Video encoding (use hevc_vaapi instead of hevc_qsv)
            '-c:v', 'hevc_vaapi',
            '-qp', str(self.config.quality),
            
            # Copy audio (if any)
            '-c:a', 'copy',
            
            # Metadata
            '-movflags', '+faststart',
            
            # Force MP4 output format (needed for .transcoding extension)
            '-f', 'mp4',
            
            # Overwrite without asking
            '-y',
            
            # Output
            str(output_file)
        ]
    
    def _verify_transcoded_file(self, original: Path, transcoded: Path) -> bool:
        """Verify transcoded file quality."""
        try:
            # Check file exists and has reasonable size
            if not transcoded.exists() or transcoded.stat().st_size < 1000:
                logger.error("Transcoded file too small or missing")
                return False
            
            # Get video info
            orig_info = self._get_video_info(original)
            trans_info = self._get_video_info(transcoded)
            
            if not orig_info or not trans_info:
                logger.error("Failed to get video info")
                return False
            
            # Check duration (within 1 second tolerance)
            duration_diff = abs(orig_info['duration'] - trans_info['duration'])
            if duration_diff > 1.0:
                logger.error(f"Duration mismatch: {duration_diff:.1f}s difference")
                return False
            
            # Check resolution
            if orig_info['width'] != trans_info['width'] or orig_info['height'] != trans_info['height']:
                logger.error("Resolution mismatch")
                return False
            
            # Check space savings
            orig_size = original.stat().st_size
            trans_size = transcoded.stat().st_size
            savings_percent = ((orig_size - trans_size) / orig_size) * 100
            
            if savings_percent < self.config.min_savings_percent:
                logger.warning(f"Insufficient savings: {savings_percent:.1f}%")
                return False
            
            # Verify file integrity
            if not self._verify_integrity(transcoded):
                logger.error("File integrity check failed")
                return False
            
            logger.info(f"Verification passed: {savings_percent:.1f}% space saved")
            return True
            
        except Exception as e:
            logger.error(f"Verification error: {e}")
            return False
    
    def _get_video_info(self, file_path: Path) -> Optional[Dict]:
        """Get video file information."""
        try:
            cmd = [
                'ffprobe',
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream=width,height,duration,r_frame_rate',
                '-of', 'json',
                str(file_path)
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return None
            
            data = json.loads(result.stdout)
            stream = data['streams'][0]
            
            # Parse duration
            duration = float(stream.get('duration', 0))
            
            return {
                'width': int(stream['width']),
                'height': int(stream['height']),
                'duration': duration
            }
            
        except Exception as e:
            logger.error(f"Error getting video info: {e}")
            return None
    
    def _verify_integrity(self, file_path: Path) -> bool:
        """Verify file is not corrupted."""
        try:
            cmd = [
                'ffmpeg',
                '-v', 'error',
                '-i', str(file_path),
                '-f', 'null',
                '-'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return result.returncode == 0 and len(result.stderr) == 0
        except Exception as e:
            logger.error(f"Integrity check error: {e}")
            return False
    
    def _replace_with_transcoded(self, original: Path, transcoded: Path):
        """Replace original with transcoded version."""
        # Get sizes
        orig_size = original.stat().st_size
        trans_size = transcoded.stat().st_size
        savings = orig_size - trans_size
        
        # Rename original to .original
        original_backup = original.with_suffix('.mp4.original')
        original.rename(original_backup)
        
        # Rename transcoded with .hevc indicator before .mp4
        # e.g., cam1_20251112_115004.mp4 -> cam1_20251112_115004.hevc.mp4
        new_name = original.stem + '.hevc.mp4'
        final_path = original.parent / new_name
        transcoded.rename(final_path)
        
        # Create metadata marker
        marker = final_path.with_suffix('.mp4.transcoded')
        delete_after = datetime.now() + timedelta(days=self.config.keep_original_days)
        
        marker.write_text(json.dumps({
            'transcoded_at': datetime.now().isoformat(),
            'original_size': orig_size,
            'transcoded_size': trans_size,
            'savings_bytes': savings,
            'original_backup': str(original_backup),
            'original_name': str(original.name),
            'delete_after': delete_after.isoformat()
        }, indent=2))
        
        # Update stats
        self.stats.total_original_bytes += orig_size
        self.stats.total_transcoded_bytes += trans_size
        self.stats.space_saved_bytes += savings
        
        logger.info(f"Replaced {original.name} -> {new_name}: saved {savings / (1024**2):.1f} MB")
    
    def _cleanup_old_originals(self):
        """Delete original files after safety period."""
        try:
            for marker in self.recordings_base.rglob('*.transcoded'):
                try:
                    metadata = json.loads(marker.read_text())
                    delete_after = datetime.fromisoformat(metadata['delete_after'])
                    
                    if datetime.now() > delete_after:
                        original_backup = Path(metadata['original_backup'])
                        if original_backup.exists():
                            size_mb = original_backup.stat().st_size / (1024**2)
                            original_backup.unlink()
                            logger.info(f"Deleted original backup: {original_backup.name} ({size_mb:.1f} MB)")
                        
                        # Delete marker
                        marker.unlink()
                        
                except Exception as e:
                    logger.error(f"Error cleaning up {marker}: {e}")
                    
        except Exception as e:
            logger.error(f"Error in cleanup: {e}")
    
    def _save_stats(self):
        """Save statistics to file."""
        try:
            stats_file = self.recordings_base / '.transcoding_stats.json'
            stats_file.write_text(json.dumps(self.stats.to_dict(), indent=2))
        except Exception as e:
            logger.error(f"Error saving stats: {e}")
    
    def _load_stats(self):
        """Load statistics from file."""
        try:
            stats_file = self.recordings_base / '.transcoding_stats.json'
            if stats_file.exists():
                data = json.loads(stats_file.read_text())
                self.stats = TranscodingStats(**data)
                logger.info(f"Loaded transcoding stats: {self.stats.files_transcoded} files transcoded")
        except Exception as e:
            logger.error(f"Error loading stats: {e}")
    
    def get_status(self) -> Dict:
        """Get current transcoder status."""
        return {
            'enabled': self.config.enabled,
            'running': self.running.is_set(),
            'current_file': str(self.current_file) if self.current_file else None,
            'in_schedule': self._in_schedule_window() if self.running.is_set() else False,
            'queue_size': self.total_queued,
            'stats': self.stats.to_dict()
        }
    
    def force_transcode_now(self) -> bool:
        """
        Force transcoding to start immediately, bypassing schedule and age restrictions.
        Scans for candidates and adds them to queue as they're found.
        Returns True if transcoding started, False if no files found.
        """
        # Start background scanner that finds files and adds to queue
        logger.info("Force transcoding: starting background scan...")
        
        # Start transcoding thread if not already running
        if not self.running.is_set():
            logger.info("Starting transcoder thread...")
            self.start()
        
        # Start background scanner thread
        Thread(
            target=self._scan_and_queue_candidates,
            daemon=True,
            name="CandidateScanner"
        ).start()
        
        return True
    
    def _scan_and_queue_candidates(self):
        """Scan for H.264 files and add them to queue as found."""
        candidates_found = 0
        skipped_stats = {
            'too_new': 0,
            'already_transcoded': 0,
            'in_progress': 0,
            'not_h264': 0,
            'checked': 0
        }
        
        logger.info("Scanning for transcode candidates...")
        
        try:
            # Scan all camera directories
            for cam_dir in self.recordings_base.iterdir():
                if not cam_dir.is_dir():
                    continue
                
                # Collect all MP4 files first (fast)
                mp4_files = list(cam_dir.glob("*.mp4"))
                
                for video_file in mp4_files:
                    skipped_stats['checked'] += 1
                    
                    # Skip if already transcoded (quick check - .hevc. in filename or marker file)
                    if self._is_transcoded(video_file):
                        skipped_stats['already_transcoded'] += 1
                        continue
                    
                    # Skip if transcoding in progress
                    if video_file.with_suffix('.mp4.transcoding').exists():
                        skipped_stats['in_progress'] += 1
                        continue
                    
                    # Check if it's H.264 (slower check with ffprobe)
                    if not self._is_h264(video_file):
                        skipped_stats['not_h264'] += 1
                        continue
                    
                    # Add to queue immediately
                    self.force_queue.put([video_file])
                    self.total_queued += 1
                    candidates_found += 1
                    
                    # Log progress every 50 files
                    if candidates_found % 50 == 0:
                        logger.info(f"Found {candidates_found} candidates so far, continuing scan...")
            
            # Final summary
            logger.info(f"Scan complete: Scanned {skipped_stats['checked']} files, "
                       f"found {candidates_found} candidates, "
                       f"{skipped_stats['already_transcoded']} already transcoded, "
                       f"{skipped_stats['in_progress']} in progress, "
                       f"{skipped_stats['not_h264']} not H.264")
            
            if candidates_found == 0:
                logger.info("No files found to transcode")
                
        except Exception as e:
            logger.error(f"Error scanning for candidates: {e}", exc_info=True)
    
    def _force_transcode_worker(self, candidates: List[Path]):
        """Worker thread for force transcoding."""
        try:
            for file in candidates:
                if not self.running.is_set():
                    break
                
                try:
                    self._transcode_one_file(file)
                except Exception as e:
                    logger.error(f"Error transcoding {file}: {e}")
                
                # Small pause between files
                time.sleep(5)
                
        finally:
            self.running.clear()
            self._save_stats()
            logger.info("Force transcoding completed")
    
    def _transcode_one_file_sync(self, file: Path):
        """Synchronous version of transcode_one_file for immediate processing."""
        try:
            self._transcode_one_file(file)
        except Exception as e:
            logger.error(f"Error in sync transcode: {e}")
