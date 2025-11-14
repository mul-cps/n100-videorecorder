#!/usr/bin/env python3
"""
Simple Web Interface for Camera Recorder
Displays recording status, logs, and disk usage
"""

import http.server
import socketserver
import os
import json
import subprocess
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# Configuration
CONFIG_FILE = "/etc/camera-recorder/camera-mapping.conf"
LOG_DIR = "/var/log/camera-recorder"
RECORDINGS_BASE = "/storage/recordings"

def load_config():
    """Load configuration from file"""
    config = {}
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip(' "')
    except FileNotFoundError:
        pass
    return config

def get_disk_usage(path):
    """Get disk usage for path"""
    try:
        result = subprocess.run(['df', '-h', path], capture_output=True, text=True)
        lines = result.stdout.strip().split('\n')
        if len(lines) > 1:
            parts = lines[1].split()
            return {
                'total': parts[1],
                'used': parts[2],
                'available': parts[3],
                'percent': parts[4]
            }
    except Exception as e:
        return {'error': str(e)}
    return {}

def get_recording_stats():
    """Get statistics about recordings"""
    stats = {'cam1': {}, 'cam2': {}}
    
    for cam in ['cam1', 'cam2']:
        cam_dir = Path(RECORDINGS_BASE) / cam
        if cam_dir.exists():
            files = list(cam_dir.glob('*.mp4'))
            total_size = sum(f.stat().st_size for f in files if f.is_file())
            
            stats[cam] = {
                'file_count': len(files),
                'total_size': f"{total_size / (1024**3):.2f} GB",
                'latest': max((f.stat().st_mtime for f in files), default=0)
            }
            
            if stats[cam]['latest']:
                stats[cam]['latest_formatted'] = datetime.fromtimestamp(
                    stats[cam]['latest']
                ).strftime('%Y-%m-%d %H:%M:%S')
    
    return stats

def get_service_status():
    """Get systemd service status"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'dual-camera-record.service'],
            capture_output=True, text=True
        )
        return result.stdout.strip()
    except Exception:
        return 'unknown'

def get_recent_logs(lines=50):
    """Get recent log entries"""
    logs = {'cam1': [], 'cam2': [], 'dual': []}
    
    for log_file, key in [
        ('camera1-qsv.log', 'cam1'),
        ('camera2-qsv.log', 'cam2'),
        ('dual-camera.log', 'dual')
    ]:
        log_path = Path(LOG_DIR) / log_file
        if log_path.exists():
            try:
                result = subprocess.run(
                    ['tail', '-n', str(lines), str(log_path)],
                    capture_output=True, text=True
                )
                logs[key] = result.stdout.strip().split('\n')
            except Exception:
                pass
    
    return logs

class CameraRecorderHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(self.get_html_page().encode())
        
        elif parsed_path.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            data = {
                'service': get_service_status(),
                'disk': get_disk_usage(RECORDINGS_BASE),
                'recordings': get_recording_stats(),
                'timestamp': datetime.now().isoformat()
            }
            self.wfile.write(json.dumps(data, indent=2).encode())
        
        elif parsed_path.path == '/api/logs':
            query = parse_qs(parsed_path.query)
            lines = int(query.get('lines', ['100'])[0])
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            logs = get_recent_logs(lines)
            self.wfile.write(json.dumps(logs, indent=2).encode())
        
        else:
            self.send_error(404, 'Not Found')
    
    def get_html_page(self):
        return """<!DOCTYPE html>
<html>
<head>
    <title>Camera Recorder Status</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #1a1a1a;
            color: #e0e0e0;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            color: #4CAF50;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #4CAF50;
        }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: #2d2d2d;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        .card h2 {
            color: #4CAF50;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #404040;
        }
        .stat-row:last-child { border-bottom: none; }
        .stat-label { color: #b0b0b0; }
        .stat-value {
            color: #fff;
            font-weight: bold;
        }
        .status-active { color: #4CAF50; }
        .status-inactive { color: #f44336; }
        .logs {
            background: #2d2d2d;
            padding: 20px;
            border-radius: 8px;
            margin-top: 20px;
        }
        .logs h2 {
            color: #4CAF50;
            margin-bottom: 15px;
        }
        .log-content {
            background: #1a1a1a;
            padding: 15px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .refresh-btn {
            background: #4CAF50;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            margin-bottom: 20px;
        }
        .refresh-btn:hover { background: #45a049; }
        .auto-refresh {
            display: inline-block;
            margin-left: 10px;
            color: #b0b0b0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎥 Camera Recorder Dashboard</h1>
        
        <button class="refresh-btn" onclick="loadStatus()">🔄 Refresh</button>
        <span class="auto-refresh">Auto-refresh: <span id="countdown">30</span>s</span>
        
        <div class="status-grid" id="statusGrid">
            <div class="card">
                <h2>Service Status</h2>
                <div id="serviceStatus">Loading...</div>
            </div>
            
            <div class="card">
                <h2>Disk Usage</h2>
                <div id="diskStatus">Loading...</div>
            </div>
            
            <div class="card">
                <h2>Camera 1</h2>
                <div id="cam1Status">Loading...</div>
            </div>
            
            <div class="card">
                <h2>Camera 2</h2>
                <div id="cam2Status">Loading...</div>
            </div>
        </div>
        
        <div class="logs">
            <h2>Recent Logs</h2>
            <div class="log-content" id="logContent">Loading...</div>
        </div>
    </div>
    
    <script>
        let countdown = 30;
        let countdownInterval;
        
        function loadStatus() {
            fetch('/api/status')
                .then(r => r.json())
                .then(data => {
                    // Service status
                    const serviceDiv = document.getElementById('serviceStatus');
                    const statusClass = data.service === 'active' ? 'status-active' : 'status-inactive';
                    serviceDiv.innerHTML = `
                        <div class="stat-row">
                            <span class="stat-label">Status:</span>
                            <span class="stat-value ${statusClass}">${data.service.toUpperCase()}</span>
                        </div>
                        <div class="stat-row">
                            <span class="stat-label">Last Updated:</span>
                            <span class="stat-value">${new Date(data.timestamp).toLocaleString()}</span>
                        </div>
                    `;
                    
                    // Disk status
                    const diskDiv = document.getElementById('diskStatus');
                    if (data.disk.error) {
                        diskDiv.innerHTML = `<div class="stat-row"><span class="stat-value">Error: ${data.disk.error}</span></div>`;
                    } else {
                        diskDiv.innerHTML = `
                            <div class="stat-row">
                                <span class="stat-label">Total:</span>
                                <span class="stat-value">${data.disk.total}</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Used:</span>
                                <span class="stat-value">${data.disk.used}</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Available:</span>
                                <span class="stat-value">${data.disk.available}</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Usage:</span>
                                <span class="stat-value">${data.disk.percent}</span>
                            </div>
                        `;
                    }
                    
                    // Camera statuses
                    ['cam1', 'cam2'].forEach(cam => {
                        const camDiv = document.getElementById(`${cam}Status`);
                        const stats = data.recordings[cam];
                        camDiv.innerHTML = `
                            <div class="stat-row">
                                <span class="stat-label">Files:</span>
                                <span class="stat-value">${stats.file_count || 0}</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Total Size:</span>
                                <span class="stat-value">${stats.total_size || '0 GB'}</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Latest:</span>
                                <span class="stat-value">${stats.latest_formatted || 'N/A'}</span>
                            </div>
                        `;
                    });
                    
                    resetCountdown();
                });
        }
        
        function loadLogs() {
            fetch('/api/logs?lines=100')
                .then(r => r.json())
                .then(logs => {
                    const logDiv = document.getElementById('logContent');
                    const allLogs = [
                        '=== Dual Camera Log ===',
                        ...logs.dual,
                        '',
                        '=== Camera 1 Log ===',
                        ...logs.cam1,
                        '',
                        '=== Camera 2 Log ===',
                        ...logs.cam2
                    ].join('\\n');
                    logDiv.textContent = allLogs || 'No logs available';
                });
        }
        
        function resetCountdown() {
            countdown = 30;
            if (countdownInterval) clearInterval(countdownInterval);
            countdownInterval = setInterval(() => {
                countdown--;
                document.getElementById('countdown').textContent = countdown;
                if (countdown <= 0) {
                    loadStatus();
                    loadLogs();
                }
            }, 1000);
        }
        
        // Initial load
        loadStatus();
        loadLogs();
        
        // Auto-refresh logs every 30 seconds
        setInterval(loadLogs, 30000);
    </script>
</body>
</html>"""

def run_server(port=8080):
    """Run the web server"""
    config = load_config()
    port = int(config.get('WEB_PORT', port))
    
    with socketserver.TCPServer(("", port), CameraRecorderHandler) as httpd:
        print(f"Camera Recorder Web Interface running on http://0.0.0.0:{port}")
        print(f"Press Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")

if __name__ == "__main__":
    run_server()
