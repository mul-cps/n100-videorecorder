"""
Camera detection and validation utilities.
"""

import os
import subprocess
import logging
import re
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class CameraDevice:
    """Represents a detected camera device."""
    device_path: str
    device_number: int
    driver: str
    card_name: str
    bus_info: str
    supported_formats: List[str]
    supported_resolutions: List[Tuple[int, int]]
    max_framerate: int
    symlinks: List[str]
    
    @property
    def is_valid(self) -> bool:
        """Check if camera device is valid and accessible."""
        return os.path.exists(self.device_path) and os.access(self.device_path, os.R_OK | os.W_OK)
    
    def supports_format(self, format_name: str) -> bool:
        """Check if camera supports a specific format."""
        return format_name.upper() in [f.upper() for f in self.supported_formats]
    
    def supports_resolution(self, width: int, height: int) -> bool:
        """Check if camera supports a specific resolution."""
        return (width, height) in self.supported_resolutions


class CameraDetector:
    """Detects and validates camera devices."""
    
    def __init__(self):
        self.v4l2_ctl = self._find_v4l2_ctl()
    
    def _find_v4l2_ctl(self) -> Optional[str]:
        """Find v4l2-ctl binary."""
        try:
            result = subprocess.run(['which', 'v4l2-ctl'], 
                                  capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            logger.warning("v4l2-ctl not found - camera detection will be limited")
            return None
    
    def detect_cameras(self) -> List[CameraDevice]:
        """Detect all available video devices."""
        cameras = []
        
        # Find all /dev/video* devices
        video_devices = sorted(Path('/dev').glob('video*'))
        
        for device_path in video_devices:
            # Skip non-character devices
            if not device_path.is_char_device():
                continue
            
            try:
                camera = self._probe_device(str(device_path))
                if camera:
                    cameras.append(camera)
                    logger.info(f"Detected camera: {camera.card_name} at {camera.device_path}")
            except Exception as e:
                logger.error(f"Error probing {device_path}: {e}")
        
        return cameras
    
    def _probe_device(self, device_path: str) -> Optional[CameraDevice]:
        """Probe a video device for capabilities."""
        if not self.v4l2_ctl:
            return self._probe_device_simple(device_path)
        
        try:
            # Get device info
            info_result = subprocess.run(
                [self.v4l2_ctl, '--device', device_path, '--info'],
                capture_output=True, text=True, timeout=5
            )
            
            if info_result.returncode != 0:
                return None
            
            # Parse device info
            driver = self._extract_field(info_result.stdout, 'Driver name')
            card_name = self._extract_field(info_result.stdout, 'Card type')
            bus_info = self._extract_field(info_result.stdout, 'Bus info')
            
            # Skip non-capture devices
            if 'video capture' not in info_result.stdout.lower():
                return None
            
            # Get supported formats
            formats_result = subprocess.run(
                [self.v4l2_ctl, '--device', device_path, '--list-formats-ext'],
                capture_output=True, text=True, timeout=5
            )
            
            formats = self._parse_formats(formats_result.stdout)
            resolutions = self._parse_resolutions(formats_result.stdout)
            max_framerate = self._parse_max_framerate(formats_result.stdout)
            
            # Find symlinks
            symlinks = self._find_symlinks(device_path)
            
            device_match = re.search(r'video(\d+)', device_path)
            device_number = int(device_match.group(1)) if device_match else 0
            
            return CameraDevice(
                device_path=device_path,
                device_number=device_number,
                driver=driver,
                card_name=card_name,
                bus_info=bus_info,
                supported_formats=formats,
                supported_resolutions=resolutions,
                max_framerate=max_framerate,
                symlinks=symlinks
            )
        
        except subprocess.TimeoutExpired:
            logger.error(f"Timeout probing device {device_path}")
            return None
        except Exception as e:
            logger.error(f"Error probing device {device_path}: {e}")
            return None
    
    def _probe_device_simple(self, device_path: str) -> Optional[CameraDevice]:
        """Simple device probe without v4l2-ctl."""
        device_match = re.search(r'video(\d+)', device_path)
        device_number = int(device_match.group(1)) if device_match else 0
        symlinks = self._find_symlinks(device_path)
        
        return CameraDevice(
            device_path=device_path,
            device_number=device_number,
            driver="unknown",
            card_name=f"Video Device {device_number}",
            bus_info="unknown",
            supported_formats=["H264", "MJPEG", "YUYV"],  # Common formats
            supported_resolutions=[(1920, 1080), (2560, 1440), (3840, 2160)],
            max_framerate=60,
            symlinks=symlinks
        )
    
    def _extract_field(self, text: str, field_name: str) -> str:
        """Extract field value from v4l2-ctl output."""
        pattern = f'{field_name}\\s*:\\s*(.+)'
        match = re.search(pattern, text)
        return match.group(1).strip() if match else "unknown"
    
    def _parse_formats(self, text: str) -> List[str]:
        """Parse supported formats from v4l2-ctl output."""
        formats = []
        for line in text.split('\n'):
            # Look for format lines like "[0]: 'H264' (H.264)"
            match = re.search(r"'([A-Z0-9]+)'", line)
            if match and 'Pixel Format' not in line:
                fmt = match.group(1)
                if fmt not in formats:
                    formats.append(fmt)
        return formats
    
    def _parse_resolutions(self, text: str) -> List[Tuple[int, int]]:
        """Parse supported resolutions from v4l2-ctl output."""
        resolutions = []
        for line in text.split('\n'):
            # Look for resolution lines like "Size: Discrete 1920x1080"
            match = re.search(r'(\d+)x(\d+)', line)
            if match:
                width, height = int(match.group(1)), int(match.group(2))
                if (width, height) not in resolutions:
                    resolutions.append((width, height))
        return sorted(resolutions, reverse=True)  # Largest first
    
    def _parse_max_framerate(self, text: str) -> int:
        """Parse maximum framerate from v4l2-ctl output."""
        max_fps = 30  # Default
        for line in text.split('\n'):
            # Look for framerate lines like "Interval: Discrete 0.017s (60.000 fps)"
            match = re.search(r'\((\d+(?:\.\d+)?)\s*fps\)', line)
            if match:
                fps = int(float(match.group(1)))
                if fps > max_fps:
                    max_fps = fps
        return max_fps
    
    def _find_symlinks(self, device_path: str) -> List[str]:
        """Find symlinks pointing to this device."""
        symlinks = []
        
        try:
            # Check /dev for symlinks
            for entry in Path('/dev').iterdir():
                if entry.is_symlink():
                    target = entry.resolve()
                    if str(target) == device_path:
                        symlinks.append(str(entry))
        except Exception as e:
            logger.debug(f"Error finding symlinks: {e}")
        
        return symlinks
    
    def validate_camera_config(self, device: str, resolution: str, 
                             framerate: int, input_format: str) -> Tuple[bool, str]:
        """
        Validate camera configuration.
        
        Returns:
            (is_valid, error_message)
        """
        # Check if device exists
        if not os.path.exists(device):
            return False, f"Device {device} does not exist"
        
        if not os.access(device, os.R_OK | os.W_OK):
            return False, f"No read/write access to {device}"
        
        if not self.v4l2_ctl:
            # Can't validate further without v4l2-ctl
            logger.warning("Cannot fully validate camera config without v4l2-ctl")
            return True, ""
        
        try:
            camera = self._probe_device(device)
            if not camera:
                return False, f"Failed to probe device {device}"
            
            # Check format support
            if not camera.supports_format(input_format):
                return False, (f"Format {input_format} not supported. "
                             f"Supported: {', '.join(camera.supported_formats)}")
            
            # Check resolution support
            width, height = map(int, resolution.split('x'))
            if not camera.supports_resolution(width, height):
                return False, (f"Resolution {resolution} not supported. "
                             f"Supported: {', '.join(f'{w}x{h}' for w, h in camera.supported_resolutions[:5])}")
            
            # Check framerate
            if framerate > camera.max_framerate:
                return False, (f"Framerate {framerate} fps exceeds maximum "
                             f"{camera.max_framerate} fps")
            
            return True, ""
        
        except Exception as e:
            return False, f"Validation error: {e}"
    
    def get_recommended_config(self, device: str) -> Dict:
        """Get recommended configuration for a camera device."""
        camera = self._probe_device(device)
        if not camera:
            return {}
        
        # Prefer H264 > MJPEG > YUYV
        preferred_formats = ['H264', 'MJPEG', 'YUYV']
        selected_format = None
        for fmt in preferred_formats:
            if camera.supports_format(fmt):
                selected_format = fmt
                break
        
        # Select highest supported resolution (prefer 16:9)
        preferred_resolutions = [
            (3840, 2160),  # 4K
            (2560, 1440),  # 1440p
            (1920, 1080),  # 1080p
            (1280, 720),   # 720p
        ]
        
        selected_resolution = None
        for res in preferred_resolutions:
            if res in camera.supported_resolutions:
                selected_resolution = res
                break
        
        if not selected_resolution and camera.supported_resolutions:
            selected_resolution = camera.supported_resolutions[0]
        
        return {
            'device': device,
            'name': camera.card_name,
            'resolution': f"{selected_resolution[0]}x{selected_resolution[1]}" if selected_resolution else "1920x1080",
            'framerate': min(60, camera.max_framerate),
            'input_format': selected_format.lower() if selected_format else 'h264',
            'enabled': True
        }
