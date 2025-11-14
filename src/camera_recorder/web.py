"""
Web interface for camera recorder using Flask.
Provides remote monitoring and control capabilities.
"""

import os
import json
import logging
import threading
import psutil
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List
from flask import Flask, render_template, jsonify, request, send_file, Response
from werkzeug.serving import make_server

logger = logging.getLogger(__name__)


class WebInterface:
    """Web interface for camera recorder."""
    
    def __init__(self, app_instance, config, port: int = 8080, host: str = '0.0.0.0'):
        """
        Initialize web interface.
        
        Args:
            app_instance: CameraRecorderApp instance
            config: SystemConfig instance
            port: Port to listen on
            host: Host to bind to
        """
        self.app_instance = app_instance
        self.config = config
        self.port = port
        self.host = host
        
        # Create Flask app
        self.flask_app = Flask(__name__, 
                              template_folder=str(Path(__file__).parent / 'templates'),
                              static_folder=str(Path(__file__).parent / 'static'))
        
        # Setup routes
        self._setup_routes()
        
        # Server instance
        self.server = None
        self.server_thread = None
    
    def _setup_routes(self):
        """Setup Flask routes."""
        
        @self.flask_app.route('/')
        def index():
            """Main dashboard page."""
            return render_template('dashboard.html', 
                                 config=self.config,
                                 cameras=self.config.cameras)
        
        @self.flask_app.route('/api/status')
        def api_status():
            """Get overall system status."""
            return jsonify(self._get_system_status())
        
        @self.flask_app.route('/api/cameras')
        def api_cameras():
            """Get camera status."""
            return jsonify(self._get_camera_status())
        
        @self.flask_app.route('/api/recordings')
        def api_recordings():
            """Get recordings list."""
            camera_id = request.args.get('camera', 'all')
            limit = int(request.args.get('limit', 50))
            return jsonify(self._get_recordings(camera_id, limit))
        
        @self.flask_app.route('/api/storage')
        def api_storage():
            """Get storage information."""
            return jsonify(self._get_storage_info())
        
        @self.flask_app.route('/api/logs')
        def api_logs():
            """Get recent logs."""
            lines = int(request.args.get('lines', 100))
            return jsonify(self._get_logs(lines))
        
        @self.flask_app.route('/api/camera/<camera_id>/start', methods=['POST'])
        def api_camera_start(camera_id):
            """Start recording on specific camera."""
            return jsonify(self._start_camera(camera_id))
        
        @self.flask_app.route('/api/camera/<camera_id>/stop', methods=['POST'])
        def api_camera_stop(camera_id):
            """Stop recording on specific camera."""
            return jsonify(self._stop_camera(camera_id))
        
        @self.flask_app.route('/api/start_all', methods=['POST'])
        def api_start_all():
            """Start all cameras."""
            return jsonify(self._start_all_cameras())
        
        @self.flask_app.route('/api/stop_all', methods=['POST'])
        def api_stop_all():
            """Stop all cameras."""
            return jsonify(self._stop_all_cameras())
        
        @self.flask_app.route('/api/download/<camera_id>/<filename>')
        def api_download(camera_id, filename):
            """Download a recording file."""
            return self._download_recording(camera_id, filename)
        
        @self.flask_app.route('/api/delete/<camera_id>/<filename>', methods=['DELETE'])
        def api_delete(camera_id, filename):
            """Delete a recording file."""
            return jsonify(self._delete_recording(camera_id, filename))
        
        @self.flask_app.route('/api/system/cpu')
        def api_system_cpu():
            """Get CPU usage."""
            return jsonify({
                'percent': psutil.cpu_percent(interval=1),
                'count': psutil.cpu_count()
            })
        
        @self.flask_app.route('/api/system/memory')
        def api_system_memory():
            """Get memory usage."""
            mem = psutil.virtual_memory()
            return jsonify({
                'total': mem.total,
                'used': mem.used,
                'percent': mem.percent,
                'available': mem.available
            })
        
        @self.flask_app.route('/api/transcoding/status')
        def api_transcoding_status():
            """Get transcoding status."""
            if hasattr(self.app_instance, 'transcoder'):
                return jsonify(self.app_instance.transcoder.get_status())
            return jsonify({'enabled': False})
        
        @self.flask_app.route('/api/transcoding/enable', methods=['POST'])
        def api_transcoding_enable():
            """Enable background transcoding."""
            if hasattr(self.app_instance, 'transcoder'):
                self.app_instance.transcoder.start()
                return jsonify({'success': True, 'message': 'Transcoding enabled'})
            return jsonify({'success': False, 'error': 'Transcoder not available'}), 400
        
        @self.flask_app.route('/api/transcoding/disable', methods=['POST'])
        def api_transcoding_disable():
            """Disable background transcoding."""
            if hasattr(self.app_instance, 'transcoder'):
                self.app_instance.transcoder.stop()
                return jsonify({'success': True, 'message': 'Transcoding disabled'})
            return jsonify({'success': False, 'error': 'Transcoder not available'}), 400
    
    def _get_system_status(self) -> Dict[str, Any]:
        """Get overall system status."""
        # Get FFmpeg processes
        ffmpeg_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
            try:
                if 'ffmpeg' in proc.info['name'].lower():
                    ffmpeg_processes.append({
                        'pid': proc.info['pid'],
                        'cpu': proc.info['cpu_percent'],
                        'memory': proc.info['memory_percent']
                    })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        return {
            'timestamp': datetime.now().isoformat(),
            'uptime': self._get_uptime(),
            'recording': len(ffmpeg_processes) > 0,
            'ffmpeg_processes': len(ffmpeg_processes),
            'processes': ffmpeg_processes,
            'transcoding_enabled': self.config.transcoding.enabled if hasattr(self.config, 'transcoding') else False
        }
    
    def _get_camera_status(self) -> List[Dict[str, Any]]:
        """Get status of all cameras."""
        cameras_status = []
        
        # Handle both dict and list camera configurations
        cameras = self.config.cameras if isinstance(self.config.cameras, dict) else {c.id: c for c in self.config.cameras}
        
        for camera_id, camera in cameras.items():
            if not camera.enabled:
                continue
                
            status = {
                'id': camera_id,
                'name': getattr(camera, 'name', camera_id),
                'device': camera.device,
                'resolution': f"{camera.width}x{camera.height}",
                'framerate': camera.framerate,
                'format': getattr(camera, 'format', camera.input_format),
                'recording': self._is_camera_recording(camera_id)
            }
            cameras_status.append(status)
        
        return cameras_status
    
    def _is_camera_recording(self, camera_id: str) -> bool:
        """Check if camera is currently recording."""
        # Check if recorder process exists for this camera
        for proc in psutil.process_iter(['cmdline']):
            try:
                cmdline = ' '.join(proc.info['cmdline'])
                if 'ffmpeg' in cmdline.lower() and camera_id in cmdline:
                    return True
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        return False
    
    def _get_recordings(self, camera_id: str, limit: int) -> Dict[str, Any]:
        """Get list of recordings."""
        recordings = []
        base_dir = Path(self.config.recording.base_directory)
        
        # Determine which cameras to list
        cameras = self.config.cameras if isinstance(self.config.cameras, dict) else {c.id: c for c in self.config.cameras}
        camera_ids = [camera_id] if camera_id != 'all' else list(cameras.keys())
        
        for cam_id in camera_ids:
            cam_dir = base_dir / cam_id
            if not cam_dir.exists():
                continue
            
            # Get all video files
            for video_file in sorted(cam_dir.glob('*.mp4'), key=lambda x: x.stat().st_mtime, reverse=True)[:limit]:
                stat = video_file.stat()
                recordings.append({
                    'camera': cam_id,
                    'filename': video_file.name,
                    'size': stat.st_size,
                    'size_mb': round(stat.st_size / (1024 * 1024), 2),
                    'created': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'created_formatted': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                })
        
        # Sort by creation time
        recordings.sort(key=lambda x: x['created'], reverse=True)
        
        return {
            'count': len(recordings),
            'recordings': recordings[:limit]
        }
    
    def _get_storage_info(self) -> Dict[str, Any]:
        """Get storage information."""
        base_dir = Path(self.config.recording.base_directory)
        
        # Get disk usage
        usage = psutil.disk_usage(str(base_dir))
        
        # Get per-camera storage
        camera_storage = {}
        cameras = self.config.cameras if isinstance(self.config.cameras, dict) else {c.id: c for c in self.config.cameras}
        
        for camera_id in cameras.keys():
            cam_dir = base_dir / camera_id
            if cam_dir.exists():
                total_size = sum(f.stat().st_size for f in cam_dir.glob('*.mp4'))
                file_count = len(list(cam_dir.glob('*.mp4')))
                camera_storage[camera_id] = {
                    'size': total_size,
                    'size_gb': round(total_size / (1024**3), 2),
                    'file_count': file_count
                }
        
        return {
            'total': usage.total,
            'used': usage.used,
            'free': usage.free,
            'percent': usage.percent,
            'total_gb': round(usage.total / (1024**3), 2),
            'used_gb': round(usage.used / (1024**3), 2),
            'free_gb': round(usage.free / (1024**3), 2),
            'camera_storage': camera_storage,
            'threshold': self.config.storage.disk_usage_threshold,
            'low_space_warning': self.config.storage.low_space_warning
        }
    
    def _get_logs(self, lines: int) -> Dict[str, Any]:
        """Get recent log entries."""
        log_file = Path('/var/log/camera-recorder/camera-recorder.log')
        log_entries = []
        
        if log_file.exists():
            try:
                with open(log_file, 'r') as f:
                    log_entries = f.readlines()[-lines:]
            except Exception as e:
                logger.error(f"Error reading logs: {e}")
                return {'error': str(e), 'entries': []}
        
        return {
            'count': len(log_entries),
            'entries': [line.strip() for line in log_entries]
        }
    
    def _start_camera(self, camera_id: str) -> Dict[str, Any]:
        """Start recording on specific camera."""
        try:
            # Check if camera exists
            cameras = self.config.cameras if isinstance(self.config.cameras, dict) else {c.id: c for c in self.config.cameras}
            if camera_id not in cameras:
                return {'success': False, 'error': f'Camera {camera_id} not found'}
            
            # Start recording via recorder
            if camera_id in self.app_instance.recorder.recorders:
                success = self.app_instance.recorder.recorders[camera_id].start()
            else:
                return {'success': False, 'error': f'Recorder for {camera_id} not initialized'}
            
            if success:
                return {'success': True, 'message': f'Camera {camera_id} started'}
            else:
                return {'success': False, 'error': f'Failed to start camera {camera_id}'}
        except Exception as e:
            logger.error(f"Error starting camera {camera_id}: {e}")
            return {'success': False, 'error': str(e)}
    
    def _stop_camera(self, camera_id: str) -> Dict[str, Any]:
        """Stop recording on specific camera."""
        try:
            if camera_id in self.app_instance.recorder.recorders:
                success = self.app_instance.recorder.recorders[camera_id].stop()
            else:
                return {'success': False, 'error': f'Recorder for {camera_id} not found'}
            
            if success:
                return {'success': True, 'message': f'Camera {camera_id} stopped'}
            else:
                return {'success': False, 'error': f'Failed to stop camera {camera_id}'}
        except Exception as e:
            logger.error(f"Error stopping camera {camera_id}: {e}")
            return {'success': False, 'error': str(e)}
    
    def _start_all_cameras(self) -> Dict[str, Any]:
        """Start all cameras."""
        try:
            results = self.app_instance.recorder.start_all()
            success_count = sum(1 for v in results.values() if v)
            
            return {
                'success': success_count > 0,
                'message': f'Started {success_count}/{len(results)} cameras',
                'results': results
            }
        except Exception as e:
            logger.error(f"Error starting all cameras: {e}")
            return {'success': False, 'error': str(e)}
    
    def _stop_all_cameras(self) -> Dict[str, Any]:
        """Stop all cameras."""
        try:
            self.app_instance.recorder.stop_all()
            return {'success': True, 'message': 'All cameras stopped'}
        except Exception as e:
            logger.error(f"Error stopping all cameras: {e}")
            return {'success': False, 'error': str(e)}
    
    def _download_recording(self, camera_id: str, filename: str):
        """Download a recording file."""
        try:
            file_path = Path(self.config.recording.base_directory) / camera_id / filename
            
            # Security check - ensure file is within recordings directory
            if not file_path.resolve().is_relative_to(Path(self.config.recording.base_directory).resolve()):
                return jsonify({'error': 'Invalid file path'}), 403
            
            if not file_path.exists():
                return jsonify({'error': 'File not found'}), 404
            
            return send_file(
                file_path,
                as_attachment=True,
                download_name=filename,
                mimetype='video/mp4'
            )
        except Exception as e:
            logger.error(f"Error downloading file: {e}")
            return jsonify({'error': str(e)}), 500
    
    def _delete_recording(self, camera_id: str, filename: str) -> Dict[str, Any]:
        """Delete a recording file."""
        try:
            file_path = Path(self.config.recording.base_directory) / camera_id / filename
            
            # Security check
            if not file_path.resolve().is_relative_to(Path(self.config.recording.base_directory).resolve()):
                return {'success': False, 'error': 'Invalid file path'}
            
            if not file_path.exists():
                return {'success': False, 'error': 'File not found'}
            
            # Delete file
            file_path.unlink()
            logger.info(f"Deleted recording: {file_path}")
            
            return {'success': True, 'message': f'Deleted {filename}'}
        except Exception as e:
            logger.error(f"Error deleting file: {e}")
            return {'success': False, 'error': str(e)}
    
    def _get_uptime(self) -> str:
        """Get system uptime."""
        try:
            boot_time = datetime.fromtimestamp(psutil.boot_time())
            uptime = datetime.now() - boot_time
            days = uptime.days
            hours, remainder = divmod(uptime.seconds, 3600)
            minutes, seconds = divmod(remainder, 60)
            return f"{days}d {hours}h {minutes}m"
        except Exception:
            return "Unknown"
    
    def start(self):
        """Start the web server in a separate thread."""
        if self.server_thread and self.server_thread.is_alive():
            logger.warning("Web server already running")
            return
        
        logger.info(f"Starting web interface on {self.host}:{self.port}")
        
        # Create server
        self.server = make_server(self.host, self.port, self.flask_app, threaded=True)
        
        # Start in thread
        self.server_thread = threading.Thread(target=self.server.serve_forever)
        self.server_thread.daemon = True
        self.server_thread.start()
        
        logger.info(f"✓ Web interface started at http://{self.host}:{self.port}")
    
    def stop(self):
        """Stop the web server."""
        if self.server:
            logger.info("Stopping web interface...")
            self.server.shutdown()
            self.server_thread.join(timeout=5)
            logger.info("✓ Web interface stopped")
