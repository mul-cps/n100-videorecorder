#!/usr/bin/env python3
"""
Example script demonstrating how to use the camera_recorder Python API.

This shows how to integrate the recording system into your own applications.
"""

import sys
import time
from pathlib import Path

# Import the camera recorder modules
from camera_recorder.config import SystemConfig
from camera_recorder.camera import CameraDetector
from camera_recorder.recorder import MultiCameraRecorder
from camera_recorder.storage import StorageManager


def example_1_basic_usage():
    """Basic usage: Load config and start recording"""
    print("=== Example 1: Basic Usage ===\n")
    
    # Load configuration
    config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')
    print(f"Loaded config with {len(config.cameras)} cameras")
    
    # Create recorder
    recorder = MultiCameraRecorder(config)
    
    # Start recording
    print("Starting recording...")
    recorder.start()
    
    # Record for 10 seconds
    time.sleep(10)
    
    # Stop recording
    print("Stopping recording...")
    recorder.stop()
    print("Recording stopped cleanly\n")


def example_2_camera_detection():
    """Detect cameras and show capabilities"""
    print("=== Example 2: Camera Detection ===\n")
    
    detector = CameraDetector()
    cameras = detector.detect_cameras()
    
    print(f"Found {len(cameras)} camera(s):\n")
    
    for device, info in cameras.items():
        print(f"Device: {device}")
        print(f"  Name: {info.get('name', 'Unknown')}")
        print(f"  Driver: {info.get('driver', 'Unknown')}")
        print(f"  Formats: {', '.join(info.get('formats', []))}")
        print(f"  Max FPS: {info.get('max_fps', 'Unknown')}")
        
        symlinks = info.get('symlinks', [])
        if symlinks:
            print(f"  Symlinks: {', '.join(symlinks)}")
        print()


def example_3_configuration_validation():
    """Validate configuration before recording"""
    print("=== Example 3: Configuration Validation ===\n")
    
    config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')
    detector = CameraDetector()
    
    all_valid = True
    for cam_id, cam_config in config.cameras.items():
        if not cam_config.enabled:
            print(f"Camera {cam_id}: Disabled, skipping")
            continue
        
        print(f"Validating camera {cam_id}...")
        is_valid = detector.validate_camera_config(cam_config)
        
        if is_valid:
            print(f"  ✓ Camera {cam_id} is valid")
        else:
            print(f"  ✗ Camera {cam_id} validation failed")
            all_valid = False
    
    if all_valid:
        print("\n✓ All cameras validated successfully\n")
    else:
        print("\n✗ Some cameras failed validation\n")
    
    return all_valid


def example_4_storage_management():
    """Manage storage and cleanup"""
    print("=== Example 4: Storage Management ===\n")
    
    config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')
    storage = StorageManager(config.storage)
    
    # Get statistics
    stats = storage.get_statistics()
    
    print(f"Total files: {stats['total_files']}")
    print(f"Total size: {stats['total_size_gb']:.2f} GB")
    print(f"Disk usage: {stats['disk_usage']:.1f}%")
    print()
    
    # Check if cleanup is needed
    if storage.should_cleanup():
        print("Cleanup is needed (old files or disk space)")
        
        # Dry run first
        print("Running dry-run cleanup...")
        files_removed, space_freed = storage.cleanup_old_recordings(dry_run=True)
        print(f"Would remove {files_removed} files, freeing {space_freed / (1024**3):.2f} GB")
        
        # Uncomment to actually cleanup:
        # storage.cleanup_old_recordings()
    else:
        print("No cleanup needed\n")


def example_5_recommended_config():
    """Generate recommended configuration for detected cameras"""
    print("=== Example 5: Recommended Configuration ===\n")
    
    detector = CameraDetector()
    cameras = detector.detect_cameras()
    
    for device, info in cameras.items():
        print(f"Device: {device}")
        recommended = detector.get_recommended_config(info)
        
        print(f"Recommended configuration:")
        print(f"  Resolution: {recommended['resolution']}")
        print(f"  Framerate: {recommended['framerate']}")
        print(f"  Format: {recommended['input_format']}")
        print()


def example_6_legacy_config():
    """Load legacy bash configuration"""
    print("=== Example 6: Legacy Config Support ===\n")
    
    legacy_path = '/etc/camera-recorder/camera-mapping.conf'
    
    if Path(legacy_path).exists():
        print(f"Loading legacy config from {legacy_path}...")
        config = SystemConfig.from_legacy_conf(legacy_path)
        
        print(f"Loaded {len(config.cameras)} cameras")
        print(f"Encoding: {config.encoding.codec}")
        print(f"Segment time: {config.recording.segment_time}s")
        
        # Convert to YAML
        yaml_output = '/tmp/converted-config.yaml'
        config.to_yaml(yaml_output)
        print(f"\nConverted to YAML: {yaml_output}\n")
    else:
        print(f"Legacy config not found at {legacy_path}\n")


def example_7_custom_recorder():
    """Create a custom recorder with specific settings"""
    print("=== Example 7: Custom Recorder ===\n")
    
    from camera_recorder.config import (
        CameraConfig, EncodingConfig, RecordingConfig, 
        StorageConfig, SystemConfig
    )
    
    # Build custom configuration
    config = SystemConfig(
        cameras={
            'test_cam': CameraConfig(
                device='/dev/video0',
                name='Test Camera',
                resolution='1920x1080',
                framerate=30,
                input_format='h264',
                enabled=True
            )
        },
        encoding=EncodingConfig(
            codec='copy',  # Stream copy, no encoding
        ),
        recording=RecordingConfig(
            segment_time=300,  # 5-minute segments
            base_directory='/tmp/test-recordings'
        ),
        storage=StorageConfig(
            cleanup_enabled=False  # Disable auto-cleanup for test
        )
    )
    
    # Create and start recorder
    recorder = MultiCameraRecorder(config)
    
    print("Custom recorder configured:")
    print(f"  Camera: {config.cameras['test_cam'].name}")
    print(f"  Resolution: {config.cameras['test_cam'].resolution}")
    print(f"  Segment time: {config.recording.segment_time}s")
    print(f"  Output dir: {config.recording.base_directory}")
    print()
    
    # In a real application, you would start recording:
    # recorder.start()
    # ... do something ...
    # recorder.stop()


def example_8_monitoring():
    """Monitor recording in progress"""
    print("=== Example 8: Monitoring ===\n")
    
    config = SystemConfig.from_yaml('/etc/camera-recorder/config.yaml')
    recorder = MultiCameraRecorder(config)
    
    # Start recording
    recorder.start()
    
    print("Recording started. Monitoring for 30 seconds...\n")
    
    for i in range(6):  # 30 seconds / 5 second intervals
        time.sleep(5)
        
        # Check if all recorders are running
        running = all(r.is_running() for r in recorder.recorders.values())
        
        print(f"[{(i+1)*5}s] Status: {'✓ All recording' if running else '✗ Some stopped'}")
        
        # Get statistics for each camera
        for cam_id, rec in recorder.recorders.items():
            stats = rec.get_statistics()
            print(f"  {cam_id}: PID {stats.get('pid', 'N/A')}, "
                  f"Running: {stats.get('running', False)}, "
                  f"Start time: {stats.get('start_time', 'N/A')}")
        print()
    
    # Stop recording
    recorder.stop()
    print("Recording stopped\n")


def main():
    """Run examples"""
    examples = {
        '1': ('Basic Usage', example_1_basic_usage),
        '2': ('Camera Detection', example_2_camera_detection),
        '3': ('Configuration Validation', example_3_configuration_validation),
        '4': ('Storage Management', example_4_storage_management),
        '5': ('Recommended Configuration', example_5_recommended_config),
        '6': ('Legacy Config Support', example_6_legacy_config),
        '7': ('Custom Recorder', example_7_custom_recorder),
        '8': ('Monitoring', example_8_monitoring),
    }
    
    if len(sys.argv) > 1:
        # Run specific example
        example_num = sys.argv[1]
        if example_num in examples:
            name, func = examples[example_num]
            print(f"\nRunning Example {example_num}: {name}\n")
            func()
        else:
            print(f"Unknown example: {example_num}")
            print(f"Available: {', '.join(examples.keys())}")
    else:
        # Show menu
        print("\n=== Camera Recorder API Examples ===\n")
        print("Usage: python3 examples/api_usage.py [example_number]\n")
        print("Available examples:")
        for num, (name, _) in examples.items():
            print(f"  {num}. {name}")
        print("\nExample: python3 examples/api_usage.py 2")
        print()


if __name__ == '__main__':
    main()
