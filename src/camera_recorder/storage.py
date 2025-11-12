"""
Storage management and cleanup utilities.
"""

import os
import logging
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Tuple

logger = logging.getLogger(__name__)


class StorageManager:
    """Manages recording storage and cleanup."""
    
    def __init__(self, base_directory: str, cleanup_days: int = 30,
                 disk_usage_threshold: int = 95, low_space_warning: int = 85):
        self.base_directory = Path(base_directory)
        self.cleanup_days = cleanup_days
        self.disk_usage_threshold = disk_usage_threshold
        self.low_space_warning = low_space_warning
    
    def get_disk_usage(self) -> Dict:
        """Get disk usage statistics."""
        try:
            stat = shutil.disk_usage(self.base_directory)
            
            return {
                'total_gb': stat.total / (1024 ** 3),
                'used_gb': stat.used / (1024 ** 3),
                'free_gb': stat.free / (1024 ** 3),
                'percent_used': (stat.used / stat.total) * 100
            }
        except Exception as e:
            logger.error(f"Error getting disk usage: {e}")
            return {}
    
    def is_space_critical(self) -> bool:
        """Check if disk space is critically low."""
        usage = self.get_disk_usage()
        if usage:
            return usage['percent_used'] > self.disk_usage_threshold
        return False
    
    def is_space_low(self) -> bool:
        """Check if disk space is low."""
        usage = self.get_disk_usage()
        if usage:
            return usage['percent_used'] > self.low_space_warning
        return False
    
    def cleanup_old_recordings(self, dry_run: bool = False) -> Dict:
        """
        Remove recordings older than cleanup_days.
        
        Returns:
            Dictionary with cleanup statistics
        """
        cutoff_date = datetime.now() - timedelta(days=self.cleanup_days)
        files_removed = 0
        space_freed_bytes = 0
        
        logger.info(f"Cleaning up recordings older than {cutoff_date}")
        
        try:
            for file_path in self.base_directory.rglob('*.mp4'):
                file_time = datetime.fromtimestamp(file_path.stat().st_mtime)
                
                if file_time < cutoff_date:
                    file_size = file_path.stat().st_size
                    
                    if dry_run:
                        logger.info(f"Would remove: {file_path} ({file_size / (1024**2):.1f} MB)")
                    else:
                        try:
                            file_path.unlink()
                            logger.info(f"Removed: {file_path}")
                            files_removed += 1
                            space_freed_bytes += file_size
                        except Exception as e:
                            logger.error(f"Error removing {file_path}: {e}")
            
            # Remove empty directories
            if not dry_run:
                for dir_path in self.base_directory.rglob('*'):
                    if dir_path.is_dir() and not any(dir_path.iterdir()):
                        try:
                            dir_path.rmdir()
                            logger.debug(f"Removed empty directory: {dir_path}")
                        except Exception as e:
                            logger.debug(f"Could not remove directory {dir_path}: {e}")
            
            return {
                'files_removed': files_removed,
                'space_freed_mb': space_freed_bytes / (1024 ** 2),
                'space_freed_gb': space_freed_bytes / (1024 ** 3),
                'dry_run': dry_run
            }
        
        except Exception as e:
            logger.error(f"Error during cleanup: {e}")
            return {'error': str(e)}
    
    def emergency_cleanup(self, target_percent: int = 80) -> Dict:
        """
        Emergency cleanup - remove oldest files until target disk usage is reached.
        
        Args:
            target_percent: Target disk usage percentage
        
        Returns:
            Dictionary with cleanup statistics
        """
        logger.warning(f"Starting emergency cleanup to reach {target_percent}% disk usage")
        
        files_removed = 0
        space_freed_bytes = 0
        max_files_to_remove = 1000  # Safety limit
        
        try:
            # Get all recording files sorted by age (oldest first)
            all_files = sorted(
                self.base_directory.rglob('*.mp4'),
                key=lambda f: f.stat().st_mtime
            )
            
            for file_path in all_files:
                # Check if we've reached target
                usage = self.get_disk_usage()
                if not usage or usage['percent_used'] <= target_percent:
                    logger.info(f"Target disk usage reached: {usage['percent_used']:.1f}%")
                    break
                
                # Safety check
                if files_removed >= max_files_to_remove:
                    logger.error(f"Emergency cleanup limit reached ({max_files_to_remove} files)")
                    break
                
                try:
                    file_size = file_path.stat().st_size
                    file_path.unlink()
                    logger.warning(f"Emergency removed: {file_path} ({file_size / (1024**2):.1f} MB)")
                    files_removed += 1
                    space_freed_bytes += file_size
                except Exception as e:
                    logger.error(f"Error removing {file_path}: {e}")
            
            return {
                'files_removed': files_removed,
                'space_freed_mb': space_freed_bytes / (1024 ** 2),
                'space_freed_gb': space_freed_bytes / (1024 ** 3),
                'final_usage': self.get_disk_usage()
            }
        
        except Exception as e:
            logger.error(f"Error during emergency cleanup: {e}")
            return {'error': str(e)}
    
    def get_recording_stats(self) -> Dict:
        """Get statistics for all recordings."""
        stats = {
            'total_files': 0,
            'total_size_gb': 0,
            'cameras': {}
        }
        
        try:
            # Check each camera directory
            for camera_dir in self.base_directory.iterdir():
                if not camera_dir.is_dir():
                    continue
                
                camera_id = camera_dir.name
                files = list(camera_dir.glob('*.mp4'))
                
                if files:
                    total_size = sum(f.stat().st_size for f in files)
                    latest_file = max(files, key=lambda f: f.stat().st_mtime)
                    oldest_file = min(files, key=lambda f: f.stat().st_mtime)
                    
                    stats['cameras'][camera_id] = {
                        'file_count': len(files),
                        'total_size_gb': total_size / (1024 ** 3),
                        'latest_file': latest_file.name,
                        'latest_time': datetime.fromtimestamp(latest_file.stat().st_mtime).isoformat(),
                        'oldest_file': oldest_file.name,
                        'oldest_time': datetime.fromtimestamp(oldest_file.stat().st_mtime).isoformat()
                    }
                    
                    stats['total_files'] += len(files)
                    stats['total_size_gb'] += total_size / (1024 ** 3)
            
            stats['disk_usage'] = self.get_disk_usage()
            
            return stats
        
        except Exception as e:
            logger.error(f"Error getting recording stats: {e}")
            return {'error': str(e)}
    
    def validate_storage(self) -> Tuple[bool, List[str]]:
        """
        Validate storage configuration.
        
        Returns:
            (is_valid, list of error messages)
        """
        errors = []
        
        # Check if base directory exists
        if not self.base_directory.exists():
            try:
                self.base_directory.mkdir(parents=True, exist_ok=True)
                logger.info(f"Created base directory: {self.base_directory}")
            except Exception as e:
                errors.append(f"Cannot create base directory: {e}")
                return False, errors
        
        # Check if writable
        test_file = self.base_directory / '.write_test'
        try:
            test_file.touch()
            test_file.unlink()
        except Exception as e:
            errors.append(f"Base directory not writable: {e}")
        
        # Check disk space
        usage = self.get_disk_usage()
        if usage:
            if usage['free_gb'] < 10:
                errors.append(f"Low disk space: only {usage['free_gb']:.1f} GB available")
            
            if usage['percent_used'] > self.disk_usage_threshold:
                errors.append(f"Disk usage critical: {usage['percent_used']:.1f}%")
        
        return len(errors) == 0, errors
