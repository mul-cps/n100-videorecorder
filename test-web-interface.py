#!/usr/bin/env python3
"""
Test script for web interface functionality
"""

import requests
import json
import sys
from time import sleep

BASE_URL = "http://localhost:8080"

def test_endpoint(method, path, description, expected_status=200):
    """Test an API endpoint"""
    url = f"{BASE_URL}{path}"
    print(f"Testing: {description}")
    print(f"  {method} {path}")
    
    try:
        if method == "GET":
            response = requests.get(url, timeout=5)
        elif method == "POST":
            response = requests.post(url, timeout=5)
        else:
            print(f"  ❌ Unsupported method: {method}")
            return False
        
        if response.status_code == expected_status:
            print(f"  ✅ Status: {response.status_code}")
            try:
                data = response.json()
                print(f"  📊 Response: {json.dumps(data, indent=2)[:200]}...")
            except:
                print(f"  📄 Content length: {len(response.content)} bytes")
            return True
        else:
            print(f"  ❌ Status: {response.status_code} (expected {expected_status})")
            return False
    except requests.exceptions.ConnectionError:
        print(f"  ❌ Connection failed - is the server running?")
        return False
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False

def main():
    """Run all tests"""
    print("=" * 60)
    print("Camera Recorder Web Interface - API Tests")
    print("=" * 60)
    print()
    
    tests = [
        ("GET", "/", "Dashboard HTML page"),
        ("GET", "/api/status", "System status"),
        ("GET", "/api/cameras", "Camera list"),
        ("GET", "/api/storage", "Storage information"),
        ("GET", "/api/system/cpu", "CPU usage"),
        ("GET", "/api/system/memory", "Memory usage"),
        ("GET", "/api/recordings?camera=all&limit=10", "Recordings list"),
        ("GET", "/api/logs?lines=10", "System logs"),
        ("GET", "/api/transcoding/status", "Transcoding status"),
    ]
    
    passed = 0
    failed = 0
    
    for method, path, description in tests:
        if test_endpoint(method, path, description):
            passed += 1
        else:
            failed += 1
        print()
        sleep(0.5)
    
    print("=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)
    
    if failed > 0:
        print()
        print("⚠️  Some tests failed. Check that:")
        print("  1. Camera recorder is running")
        print("  2. Web interface is enabled in config")
        print("  3. Port 8080 is not blocked by firewall")
        print("  4. Service logs: journalctl -u camera-recorder-python -f")
        sys.exit(1)
    else:
        print()
        print("✅ All tests passed!")
        print(f"🌐 Access web interface at: {BASE_URL}")
        sys.exit(0)

if __name__ == "__main__":
    main()
