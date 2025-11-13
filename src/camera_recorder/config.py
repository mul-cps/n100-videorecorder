"""
Configuration management for camera recorder system.
"""

import os
import yaml
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class CameraConfig:
    """Configuration for a single camera."""
    device: str
    name: str
    resolution: str = "2560x1440"
    framerate: int = 60
    input_format: str = "h264"
    enabled: bool = True
    
    @property
    def width(self) -> int:
        """Get width from resolution string."""
        return int(self.resolution.split('x')[0])
    
    @property
    def height(self) -> int:
        """Get height from resolution string."""
        return int(self.resolution.split('x')[1])


@dataclass
class EncodingConfig:
    """Video encoding configuration."""
    codec: str = "copy"  # copy, hevc_qsv, h264_qsv
    preset: str = "fast"
    quality: int = 23
    bitrate_mode: str = "VBR"
    target_bitrate: int = 8000
    max_bitrate: int = 12000
    gop_size: int = 60
    ref_frames: int = 3
    lookahead: bool = True
    extra_hw_frames: int = 64


@dataclass
class RecordingConfig:
    """Recording session configuration."""
    segment_time: int = 1800  # 30 minutes
    container_format: str = "mp4"
    base_directory: str = "/storage/recordings"
    flush_packets: bool = False
    movflags: str = "faststart+frag_keyframe"
    
    @property
    def recordings_path(self) -> Path:
        """Get recordings directory as Path object."""
        return Path(self.base_directory)


@dataclass
class StorageConfig:
    """Storage management configuration."""
    cleanup_enabled: bool = True
    cleanup_days: int = 30
    disk_usage_threshold: int = 95
    low_space_warning: int = 85


@dataclass
class TranscodingConfig:
    """Background transcoding configuration."""
    enabled: bool = False
    min_age_days: int = 7
    run_schedule_start: str = "02:00"
    run_schedule_end: str = "06:00"
    max_cpu_percent: float = 15.0
    max_io_wait: float = 5.0
    codec: str = "hevc_qsv"
    preset: str = "medium"
    quality: int = 23
    keep_original_days: int = 1
    min_free_space_gb: int = 100
    min_savings_percent: float = 10.0
    verify_quality: bool = True


@dataclass
class SystemConfig:
    """Complete system configuration."""
    cameras: Dict[str, CameraConfig] = field(default_factory=dict)
    encoding: EncodingConfig = field(default_factory=EncodingConfig)
    recording: RecordingConfig = field(default_factory=RecordingConfig)
    storage: StorageConfig = field(default_factory=StorageConfig)
    transcoding: TranscodingConfig = field(default_factory=TranscodingConfig)
    vaapi_driver: str = "iHD"
    log_level: str = "INFO"
    
    @classmethod
    def from_yaml(cls, config_path: str) -> 'SystemConfig':
        """Load configuration from YAML file."""
        with open(config_path, 'r') as f:
            data = yaml.safe_load(f)
        
        config = cls()
        
        # Parse camera configurations
        if 'cameras' in data:
            for cam_id, cam_data in data['cameras'].items():
                config.cameras[cam_id] = CameraConfig(**cam_data)
        
        # Parse encoding configuration
        if 'encoding' in data:
            config.encoding = EncodingConfig(**data['encoding'])
        
        # Parse recording configuration
        if 'recording' in data:
            config.recording = RecordingConfig(**data['recording'])
        
        # Parse storage configuration
        if 'storage' in data:
            config.storage = StorageConfig(**data['storage'])
        
        # Parse transcoding configuration
        if 'transcoding' in data:
            config.transcoding = TranscodingConfig(**data['transcoding'])
        
        # Parse system settings
        config.vaapi_driver = data.get('vaapi_driver', 'iHD')
        config.log_level = data.get('log_level', 'INFO')
        
        return config
    
    @classmethod
    def from_legacy_conf(cls, conf_path: str) -> 'SystemConfig':
        """Load configuration from legacy bash configuration file."""
        config = cls()
        env_vars = {}
        
        # Parse bash configuration file
        with open(conf_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove inline comments (everything after #)
                    if '#' in value:
                        value = value.split('#')[0].strip()
                    # Remove quotes from value
                    value = value.strip('"').strip("'")
                    env_vars[key] = value
        
        # Map to camera configurations
        if 'CAMERA1_DEVICE' in env_vars:
            config.cameras['cam1'] = CameraConfig(
                device=env_vars.get('CAMERA1_DEVICE', '/dev/video0'),
                name=env_vars.get('CAMERA1_NAME', 'Camera 1'),
                resolution=env_vars.get('CAMERA1_RESOLUTION', '2560x1440'),
                framerate=int(env_vars.get('CAMERA1_FRAMERATE', '60')),
                input_format=env_vars.get('CAMERA1_FORMAT', 'h264')
            )
        
        if 'CAMERA2_DEVICE' in env_vars:
            config.cameras['cam2'] = CameraConfig(
                device=env_vars.get('CAMERA2_DEVICE', '/dev/video2'),
                name=env_vars.get('CAMERA2_NAME', 'Camera 2'),
                resolution=env_vars.get('CAMERA2_RESOLUTION', '2560x1440'),
                framerate=int(env_vars.get('CAMERA2_FRAMERATE', '60')),
                input_format=env_vars.get('CAMERA2_FORMAT', 'h264')
            )
        
        # Map encoding settings
        config.encoding = EncodingConfig(
            codec=env_vars.get('ENCODING_CODEC', 'copy'),
            preset=env_vars.get('ENCODING_PRESET', 'fast'),
            quality=int(env_vars.get('ENCODING_QUALITY', '23')),
            bitrate_mode=env_vars.get('BITRATE_MODE', 'VBR'),
            target_bitrate=int(env_vars.get('TARGET_BITRATE', '8000')),
            max_bitrate=int(env_vars.get('MAX_BITRATE', '12000')),
            gop_size=int(env_vars.get('GOP_SIZE', '60')),
            ref_frames=int(env_vars.get('REF_FRAMES', '3')),
            lookahead=env_vars.get('LOOKAHEAD_ENABLED', '1') == '1',
            extra_hw_frames=int(env_vars.get('EXTRA_HW_FRAMES', '64'))
        )
        
        # Map recording settings
        config.recording = RecordingConfig(
            segment_time=int(env_vars.get('SEGMENT_TIME', '1800')),
            container_format=env_vars.get('CONTAINER_FORMAT', 'mp4'),
            base_directory=env_vars.get('RECORDINGS_BASE', '/storage/recordings'),
            flush_packets=env_vars.get('FLUSH_PACKETS', '0') == '1',
            movflags=env_vars.get('MOVFLAGS', 'faststart+frag_keyframe')
        )
        
        # Map storage settings
        config.storage = StorageConfig(
            cleanup_enabled=env_vars.get('CLEANUP_ENABLED', 'true').lower() == 'true',
            cleanup_days=int(env_vars.get('CLEANUP_DAYS', '30')),
            disk_usage_threshold=int(env_vars.get('DISK_USAGE_THRESHOLD', '95')),
            low_space_warning=int(env_vars.get('LOW_SPACE_WARNING', '85'))
        )
        
        config.vaapi_driver = env_vars.get('VAAPI_DRIVER', 'iHD')
        
        return config
    
    def to_yaml(self, output_path: str) -> None:
        """Save configuration to YAML file."""
        data = {
            'cameras': {
                cam_id: {
                    'device': cam.device,
                    'name': cam.name,
                    'resolution': cam.resolution,
                    'framerate': cam.framerate,
                    'input_format': cam.input_format,
                    'enabled': cam.enabled
                }
                for cam_id, cam in self.cameras.items()
            },
            'encoding': {
                'codec': self.encoding.codec,
                'preset': self.encoding.preset,
                'quality': self.encoding.quality,
                'bitrate_mode': self.encoding.bitrate_mode,
                'target_bitrate': self.encoding.target_bitrate,
                'max_bitrate': self.encoding.max_bitrate,
                'gop_size': self.encoding.gop_size,
                'ref_frames': self.encoding.ref_frames,
                'lookahead': self.encoding.lookahead,
                'extra_hw_frames': self.encoding.extra_hw_frames
            },
            'recording': {
                'segment_time': self.recording.segment_time,
                'container_format': self.recording.container_format,
                'base_directory': self.recording.base_directory,
                'flush_packets': self.recording.flush_packets,
                'movflags': self.recording.movflags
            },
            'storage': {
                'cleanup_enabled': self.storage.cleanup_enabled,
                'cleanup_days': self.storage.cleanup_days,
                'disk_usage_threshold': self.storage.disk_usage_threshold,
                'low_space_warning': self.storage.low_space_warning
            },
            'transcoding': {
                'enabled': self.transcoding.enabled,
                'min_age_days': self.transcoding.min_age_days,
                'run_schedule_start': self.transcoding.run_schedule_start,
                'run_schedule_end': self.transcoding.run_schedule_end,
                'max_cpu_percent': self.transcoding.max_cpu_percent,
                'max_io_wait': self.transcoding.max_io_wait,
                'codec': self.transcoding.codec,
                'preset': self.transcoding.preset,
                'quality': self.transcoding.quality,
                'keep_original_days': self.transcoding.keep_original_days,
                'min_free_space_gb': self.transcoding.min_free_space_gb,
                'min_savings_percent': self.transcoding.min_savings_percent,
                'verify_quality': self.transcoding.verify_quality
            },
            'vaapi_driver': self.vaapi_driver,
            'log_level': self.log_level
        }
        
        with open(output_path, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
        
        logger.info(f"Configuration saved to {output_path}")


def load_config(config_path: Optional[str] = None) -> SystemConfig:
    """
    Load system configuration from file.
    
    Tries to load from:
    1. Provided config_path
    2. /etc/camera-recorder/config.yaml
    3. /etc/camera-recorder/camera-mapping.conf (legacy)
    4. Default configuration
    """
    if config_path and os.path.exists(config_path):
        if config_path.endswith('.yaml') or config_path.endswith('.yml'):
            return SystemConfig.from_yaml(config_path)
        else:
            return SystemConfig.from_legacy_conf(config_path)
    
    # Try standard locations
    yaml_path = '/etc/camera-recorder/config.yaml'
    legacy_path = '/etc/camera-recorder/camera-mapping.conf'
    
    if os.path.exists(yaml_path):
        logger.info(f"Loading configuration from {yaml_path}")
        return SystemConfig.from_yaml(yaml_path)
    elif os.path.exists(legacy_path):
        logger.info(f"Loading legacy configuration from {legacy_path}")
        return SystemConfig.from_legacy_conf(legacy_path)
    else:
        logger.warning("No configuration file found, using defaults")
        return SystemConfig()
