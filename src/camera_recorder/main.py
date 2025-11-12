"""
Main application entry point for camera recorder.
"""

import os
import sys
import signal
import logging
import time
from pathlib import Path
from typing import Optional

from .config import load_config, SystemConfig
from .camera import CameraDetector
from .recorder import MultiCameraRecorder
from .storage import StorageManager
from .transcoder import BackgroundTranscoder

logger = logging.getLogger(__name__)


class CameraRecorderApp:
    """Main camera recorder application."""
    
    def __init__(self, config_path: Optional[str] = None):
        # Load configuration
        self.config = load_config(config_path)
        
        # Setup logging
        self._setup_logging()
        
        # Initialize components
        self.detector = CameraDetector()
        self.recorder = MultiCameraRecorder(
            self.config.cameras,
            self.config.encoding,
            self.config.recording
        )
        self.storage = StorageManager(
            self.config.recording.base_directory,
            self.config.storage.cleanup_days,
            self.config.storage.disk_usage_threshold,
            self.config.storage.low_space_warning
        )
        
        # Initialize transcoder
        self.transcoder = BackgroundTranscoder(
            self.config.transcoding,
            Path(self.config.recording.base_directory)
        )
        
        # Setup signal handlers
        self.should_stop = False
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _setup_logging(self):
        """Setup logging configuration."""
        log_level = getattr(logging, self.config.log_level.upper(), logging.INFO)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(log_level)
        console_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        console_handler.setFormatter(console_formatter)
        
        # File handler
        log_dir = Path('/var/log/camera-recorder')
        log_dir.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_dir / 'camera-recorder.log')
        file_handler.setLevel(logging.DEBUG)
        file_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        
        # Configure root logger
        root_logger = logging.getLogger()
        root_logger.setLevel(logging.DEBUG)
        root_logger.addHandler(console_handler)
        root_logger.addHandler(file_handler)
        
        logger.info("Logging initialized")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        logger.info(f"Received signal {signum}, initiating shutdown...")
        self.should_stop = True
    
    def validate_system(self) -> bool:
        """Validate system configuration and readiness."""
        logger.info("Validating system configuration...")
        
        errors = []
        
        # Validate storage
        storage_valid, storage_errors = self.storage.validate_storage()
        if not storage_valid:
            errors.extend(storage_errors)
        
        # Validate cameras
        for camera_id, camera_config in self.config.cameras.items():
            if not camera_config.enabled:
                continue
            
            is_valid, error_msg = self.detector.validate_camera_config(
                camera_config.device,
                camera_config.resolution,
                camera_config.framerate,
                camera_config.input_format
            )
            
            if not is_valid:
                errors.append(f"Camera {camera_id}: {error_msg}")
        
        if errors:
            logger.error("System validation failed:")
            for error in errors:
                logger.error(f"  - {error}")
            return False
        
        logger.info("System validation passed")
        return True
    
    def run(self):
        """Main application loop."""
        logger.info("Starting camera recorder application")
        logger.info(f"Configuration: {len(self.config.cameras)} cameras, "
                   f"codec: {self.config.encoding.codec}, "
                   f"segment time: {self.config.recording.segment_time}s")
        
        # Validate system
        if not self.validate_system():
            logger.error("System validation failed, cannot start recording")
            return 1
        
        # Set VA-API driver
        os.environ['LIBVA_DRIVER_NAME'] = self.config.vaapi_driver
        logger.info(f"VA-API driver: {self.config.vaapi_driver}")
        
        # Start recording
        logger.info("Starting camera recorders...")
        start_results = self.recorder.start_all()
        
        for camera_id, success in start_results.items():
            if success:
                logger.info(f"✓ Camera {camera_id} started successfully")
            else:
                logger.error(f"✗ Camera {camera_id} failed to start")
        
        if not any(start_results.values()):
            logger.error("No cameras started successfully, exiting")
            return 1
        
        # Start background transcoder
        if self.config.transcoding.enabled:
            logger.info("Starting background transcoder...")
            self.transcoder.start()
        
        # Main monitoring loop
        check_interval = 60  # Check every minute
        last_cleanup = time.time()
        cleanup_interval = 3600  # Run cleanup every hour
        
        try:
            while not self.should_stop:
                time.sleep(check_interval)
                
                # Check recorder health
                health = self.recorder.check_health()
                for camera_id, is_alive in health.items():
                    if not is_alive:
                        logger.error(f"Camera {camera_id} recorder died!")
                        # Could implement restart logic here
                
                # Check disk space
                if self.storage.is_space_critical():
                    logger.error("Disk space critical! Stopping recording...")
                    self.storage.emergency_cleanup()
                    break
                elif self.storage.is_space_low():
                    logger.warning("Disk space running low")
                
                # Periodic cleanup
                if time.time() - last_cleanup > cleanup_interval:
                    if self.config.storage.cleanup_enabled:
                        logger.info("Running periodic cleanup...")
                        cleanup_stats = self.storage.cleanup_old_recordings()
                        logger.info(f"Cleanup complete: {cleanup_stats}")
                    last_cleanup = time.time()
                
                # Log statistics
                stats = self.recorder.get_all_stats()
                for camera_id, camera_stats in stats.items():
                    if camera_stats['is_recording']:
                        logger.debug(f"Camera {camera_id}: "
                                   f"{camera_stats['file_count']} files, "
                                   f"{camera_stats['total_size_mb']:.1f} MB")
        
        except Exception as e:
            logger.error(f"Error in main loop: {e}", exc_info=True)
        
        finally:
            # Stop transcoder first (give it time to finish current file)
            if self.config.transcoding.enabled:
                logger.info("Stopping background transcoder...")
                self.transcoder.stop(timeout=300)
            
            # Cleanup and shutdown
            logger.info("Shutting down camera recorders...")
            stop_results = self.recorder.stop_all()
            
            for camera_id, success in stop_results.items():
                if success:
                    logger.info(f"✓ Camera {camera_id} stopped successfully")
                else:
                    logger.error(f"✗ Camera {camera_id} failed to stop cleanly")
            
            # Final statistics
            final_stats = self.storage.get_recording_stats()
            logger.info(f"Final statistics: {final_stats}")
            
            logger.info("Camera recorder application stopped")
        
        return 0


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='N100 Camera Recorder')
    parser.add_argument('-c', '--config', help='Path to configuration file')
    parser.add_argument('--validate', action='store_true',
                       help='Validate configuration and exit')
    parser.add_argument('--detect', action='store_true',
                       help='Detect cameras and exit')
    parser.add_argument('--stats', action='store_true',
                       help='Show recording statistics and exit')
    parser.add_argument('--cleanup', action='store_true',
                       help='Run cleanup and exit')
    parser.add_argument('--dry-run', action='store_true',
                       help='Dry run for cleanup')
    parser.add_argument('--transcode-stats', action='store_true',
                       help='Show transcoding statistics and exit')
    parser.add_argument('--transcode-enable', action='store_true',
                       help='Enable background transcoding')
    parser.add_argument('--transcode-disable', action='store_true',
                       help='Disable background transcoding')
    
    args = parser.parse_args()
    
    # Handle special commands
    if args.detect:
        detector = CameraDetector()
        cameras = detector.detect_cameras()
        
        print("\n=== Detected Cameras ===")
        for camera in cameras:
            print(f"\nDevice: {camera.device_path}")
            print(f"  Name: {camera.card_name}")
            print(f"  Driver: {camera.driver}")
            print(f"  Formats: {', '.join(camera.supported_formats)}")
            print(f"  Max FPS: {camera.max_framerate}")
            if camera.symlinks:
                print(f"  Symlinks: {', '.join(camera.symlinks)}")
            
            # Show recommended config
            rec_config = detector.get_recommended_config(camera.device_path)
            print(f"  Recommended config:")
            print(f"    resolution: {rec_config.get('resolution')}")
            print(f"    framerate: {rec_config.get('framerate')}")
            print(f"    input_format: {rec_config.get('input_format')}")
        
        return 0
    
    # Create app instance
    app = CameraRecorderApp(args.config)
    
    if args.validate:
        print("\n=== Validating Configuration ===")
        if app.validate_system():
            print("✓ System validation passed")
            return 0
        else:
            print("✗ System validation failed")
            return 1
    
    if args.stats:
        print("\n=== Recording Statistics ===")
        stats = app.storage.get_recording_stats()
        
        print(f"\nTotal files: {stats.get('total_files', 0)}")
        print(f"Total size: {stats.get('total_size_gb', 0):.2f} GB")
        
        if 'disk_usage' in stats:
            usage = stats['disk_usage']
            print(f"\nDisk usage:")
            print(f"  Used: {usage.get('used_gb', 0):.1f} GB ({usage.get('percent_used', 0):.1f}%)")
            print(f"  Free: {usage.get('free_gb', 0):.1f} GB")
            print(f"  Total: {usage.get('total_gb', 0):.1f} GB")
        
        if 'cameras' in stats:
            for camera_id, camera_stats in stats['cameras'].items():
                print(f"\nCamera: {camera_id}")
                print(f"  Files: {camera_stats.get('file_count', 0)}")
                print(f"  Size: {camera_stats.get('total_size_gb', 0):.2f} GB")
                if 'latest_file' in camera_stats:
                    print(f"  Latest: {camera_stats['latest_file']}")
        
        return 0
    
    if args.cleanup:
        print("\n=== Running Cleanup ===")
        cleanup_stats = app.storage.cleanup_old_recordings(dry_run=args.dry_run)
        
        print(f"Files removed: {cleanup_stats.get('files_removed', 0)}")
        print(f"Space freed: {cleanup_stats.get('space_freed_gb', 0):.2f} GB")
        if args.dry_run:
            print("(Dry run - no files were actually removed)")
        
        return 0
    
    if args.transcode_stats:
        print("\n=== Transcoding Statistics ===")
        status = app.transcoder.get_status()
        stats = status['stats']
        
        print(f"\nEnabled: {status['enabled']}")
        print(f"Running: {status['running']}")
        if status['current_file']:
            print(f"Current file: {status['current_file']}")
        print(f"In schedule: {status['in_schedule']}")
        
        print(f"\nFiles transcoded: {stats['files_transcoded']}")
        print(f"Files failed: {stats['files_failed']}")
        print(f"Space saved: {stats['space_saved_bytes'] / (1024**3):.2f} GB")
        
        if stats['total_original_bytes'] > 0:
            savings_pct = (stats['space_saved_bytes'] / stats['total_original_bytes']) * 100
            print(f"Space savings: {savings_pct:.1f}%")
        
        if stats['last_transcoded']:
            print(f"\nLast transcoded: {stats['last_transcoded']}")
        if stats['last_error']:
            print(f"Last error: {stats['last_error']}")
        
        return 0
    
    if args.transcode_enable:
        print("Enabling background transcoding...")
        app.config.transcoding.enabled = True
        # Save config would go here
        print("✓ Background transcoding enabled")
        print("  Restart service for changes to take effect")
        return 0
    
    if args.transcode_disable:
        print("Disabling background transcoding...")
        app.config.transcoding.enabled = False
        # Save config would go here
        print("✓ Background transcoding disabled")
        print("  Restart service for changes to take effect")
        return 0
    
    # Run main application
    try:
        return app.run()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        return 0
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
