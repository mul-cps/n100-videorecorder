"""
FFmpeg-based video recorder with QSV support.
"""

import os
import subprocess
import logging
import signal
import time
from pathlib import Path
from typing import List, Optional, Dict
from datetime import datetime
from threading import Thread, Event

from .config import CameraConfig, EncodingConfig, RecordingConfig

logger = logging.getLogger(__name__)


class FFmpegRecorder:
    """Manages FFmpeg recording process for a single camera."""
    
    def __init__(self, camera_id: str, camera_config: CameraConfig,
                 encoding_config: EncodingConfig, recording_config: RecordingConfig):
        self.camera_id = camera_id
        self.camera_config = camera_config
        self.encoding_config = encoding_config
        self.recording_config = recording_config
        
        self.process: Optional[subprocess.Popen] = None
        self.is_recording = Event()
        self.output_dir = recording_config.recordings_path / camera_id
        
        # Ensure output directory exists
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Find FFmpeg binary
        self.ffmpeg_bin = self._find_ffmpeg()
    
    def _find_ffmpeg(self) -> str:
        """Find suitable FFmpeg binary."""
        candidates = [
            '/usr/lib/jellyfin-ffmpeg/ffmpeg',
            '/usr/local/bin/ffmpeg-qsv',
            'ffmpeg'
        ]
        
        for candidate in candidates:
            try:
                result = subprocess.run([candidate, '-version'],
                                      capture_output=True, timeout=5)
                if result.returncode == 0:
                    logger.info(f"Using FFmpeg: {candidate}")
                    return candidate
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue
        
        raise RuntimeError("FFmpeg not found")
    
    def build_ffmpeg_command(self) -> List[str]:
        """Build FFmpeg command line arguments."""
        cmd = [self.ffmpeg_bin]
        
        # Input configuration
        cmd.extend([
            '-f', 'v4l2',
            '-input_format', self.camera_config.input_format,
            '-video_size', self.camera_config.resolution,
            '-framerate', str(self.camera_config.framerate),
            '-i', self.camera_config.device
        ])
        
        # Encoding configuration
        if self.encoding_config.codec == 'copy':
            # Stream copy mode - no transcoding
            cmd.extend(['-c:v', 'copy'])
        elif 'qsv' in self.encoding_config.codec:
            # QSV hardware encoding
            cmd.extend([
                '-init_hw_device', 'qsv=hw',
                '-filter_hw_device', 'hw',
                '-vf', f'hwupload=extra_hw_frames={self.encoding_config.extra_hw_frames},format=qsv',
                '-c:v', self.encoding_config.codec,
                '-preset', self.encoding_config.preset,
                '-global_quality', str(self.encoding_config.quality)
            ])
            
            if self.encoding_config.lookahead:
                cmd.extend(['-look_ahead', '1'])
            
            if self.encoding_config.bitrate_mode == 'VBR':
                cmd.extend([
                    '-b:v', f'{self.encoding_config.target_bitrate}k',
                    '-maxrate', f'{self.encoding_config.max_bitrate}k'
                ])
            
            cmd.extend([
                '-g', str(self.encoding_config.gop_size),
                '-bf', str(self.encoding_config.ref_frames)
            ])
        else:
            # Software encoding
            cmd.extend([
                '-c:v', self.encoding_config.codec,
                '-preset', self.encoding_config.preset,
                '-crf', str(self.encoding_config.quality)
            ])
        
        # Output configuration - segmented recording
        output_pattern = str(self.output_dir / f'{self.camera_id}_%Y%m%d_%H%M%S.{self.recording_config.container_format}')
        
        cmd.extend([
            '-f', 'segment',
            '-segment_time', str(self.recording_config.segment_time),
            '-segment_format', self.recording_config.container_format,
            '-reset_timestamps', '1',
            '-strftime', '1'
        ])
        
        # Add movflags if specified
        if self.recording_config.movflags:
            cmd.extend([
                '-segment_format_options',
                f'movflags={self.recording_config.movflags}'
            ])
        
        if not self.recording_config.flush_packets:
            cmd.extend(['-flush_packets', '0'])
        
        cmd.append(output_pattern)
        
        return cmd
    
    def start(self) -> bool:
        """Start recording."""
        if self.is_recording.is_set():
            logger.warning(f"{self.camera_id}: Already recording")
            return False
        
        try:
            cmd = self.build_ffmpeg_command()
            logger.info(f"{self.camera_id}: Starting recording")
            logger.debug(f"{self.camera_id}: Command: {' '.join(cmd)}")
            
            # Start FFmpeg process
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, 'LIBVA_DRIVER_NAME': 'iHD'}
            )
            
            self.is_recording.set()
            
            # Start output monitoring thread
            Thread(target=self._monitor_output, daemon=True).start()
            
            logger.info(f"{self.camera_id}: Recording started (PID: {self.process.pid})")
            return True
        
        except Exception as e:
            logger.error(f"{self.camera_id}: Failed to start recording: {e}")
            self.is_recording.clear()
            return False
    
    def stop(self, timeout: int = 15) -> bool:
        """Stop recording gracefully."""
        if not self.is_recording.is_set():
            logger.warning(f"{self.camera_id}: Not recording")
            return False
        
        if not self.process:
            self.is_recording.clear()
            return False
        
        try:
            logger.info(f"{self.camera_id}: Stopping recording (PID: {self.process.pid})")
            
            # Send SIGINT for graceful shutdown (FFmpeg closes files properly)
            self.process.send_signal(signal.SIGINT)
            
            # Wait for process to terminate
            try:
                self.process.wait(timeout=timeout)
                logger.info(f"{self.camera_id}: Recording stopped cleanly")
            except subprocess.TimeoutExpired:
                logger.warning(f"{self.camera_id}: Timeout waiting for FFmpeg, forcing termination")
                self.process.kill()
                self.process.wait(timeout=5)
            
            self.is_recording.clear()
            return True
        
        except Exception as e:
            logger.error(f"{self.camera_id}: Error stopping recording: {e}")
            return False
    
    def is_alive(self) -> bool:
        """Check if recording process is alive."""
        if not self.process:
            return False
        return self.process.poll() is None
    
    def _monitor_output(self):
        """Monitor FFmpeg output for errors."""
        if not self.process or not self.process.stderr:
            return
        
        log_file = Path('/var/log/camera-recorder') / f'{self.camera_id}.log'
        log_file.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            with open(log_file, 'a') as f:
                f.write(f"\n=== Recording started at {datetime.now()} ===\n")
                
                for line in self.process.stderr:
                    try:
                        line_text = line.decode('utf-8', errors='replace').strip()
                        f.write(line_text + '\n')
                        
                        # Log errors and warnings
                        if 'error' in line_text.lower():
                            logger.error(f"{self.camera_id}: {line_text}")
                        elif 'warning' in line_text.lower():
                            logger.warning(f"{self.camera_id}: {line_text}")
                    except Exception as e:
                        logger.debug(f"Error processing FFmpeg output: {e}")
                
                f.write(f"=== Recording ended at {datetime.now()} ===\n")
        
        except Exception as e:
            logger.error(f"{self.camera_id}: Error monitoring output: {e}")
    
    def get_stats(self) -> Dict:
        """Get recording statistics."""
        stats = {
            'camera_id': self.camera_id,
            'is_recording': self.is_recording.is_set(),
            'is_alive': self.is_alive(),
            'pid': self.process.pid if self.process else None,
            'output_dir': str(self.output_dir),
            'file_count': 0,
            'total_size_mb': 0,
            'latest_file': None
        }
        
        if self.output_dir.exists():
            files = list(self.output_dir.glob(f'{self.camera_id}_*.{self.recording_config.container_format}'))
            stats['file_count'] = len(files)
            
            if files:
                total_size = sum(f.stat().st_size for f in files)
                stats['total_size_mb'] = total_size / (1024 * 1024)
                
                latest = max(files, key=lambda f: f.stat().st_mtime)
                stats['latest_file'] = {
                    'name': latest.name,
                    'size_mb': latest.stat().st_size / (1024 * 1024),
                    'modified': datetime.fromtimestamp(latest.stat().st_mtime).isoformat()
                }
        
        return stats


class MultiCameraRecorder:
    """Manages multiple camera recorders."""
    
    def __init__(self, cameras: Dict[str, CameraConfig],
                 encoding_config: EncodingConfig,
                 recording_config: RecordingConfig):
        self.recorders: Dict[str, FFmpegRecorder] = {}
        
        for camera_id, camera_config in cameras.items():
            if camera_config.enabled:
                self.recorders[camera_id] = FFmpegRecorder(
                    camera_id, camera_config, encoding_config, recording_config
                )
    
    def start_all(self) -> Dict[str, bool]:
        """Start all camera recorders."""
        results = {}
        for camera_id, recorder in self.recorders.items():
            results[camera_id] = recorder.start()
            time.sleep(0.5)  # Slight delay between starts
        return results
    
    def stop_all(self, timeout: int = 15) -> Dict[str, bool]:
        """Stop all camera recorders."""
        results = {}
        for camera_id, recorder in self.recorders.items():
            results[camera_id] = recorder.stop(timeout)
        return results
    
    def get_all_stats(self) -> Dict[str, Dict]:
        """Get statistics for all recorders."""
        return {
            camera_id: recorder.get_stats()
            for camera_id, recorder in self.recorders.items()
        }
    
    def check_health(self) -> Dict[str, bool]:
        """Check health of all recorders."""
        return {
            camera_id: recorder.is_alive()
            for camera_id, recorder in self.recorders.items()
        }
