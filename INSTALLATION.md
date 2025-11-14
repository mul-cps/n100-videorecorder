# Installation Guide

The Camera Recorder supports multiple installation methods to accommodate different Python environments and system configurations.

## Installation Methods

### Method 1: Virtual Environment (Recommended) ✅

**Best for:** Modern Debian/Ubuntu systems (12+), development, isolated installations

```bash
./install.sh
```

This will:
- Automatically create a Python virtual environment (`venv/`)
- Install all dependencies in isolation
- Not interfere with system Python packages

**Usage after installation:**
```bash
# Activate virtual environment
source venv/bin/activate

# Run camera recorder
camera-recorder

# Or run directly without activation
./venv/bin/camera-recorder
```

**For systemd service with venv:**
```bash
sudo nano /etc/systemd/system/camera-recorder-python.service
# Update ExecStart to:
ExecStart=/home/bjoern/git/n100-videorecorder/venv/bin/camera-recorder -c /etc/camera-recorder/config.yaml
```

---

### Method 2: System-Wide Installation

**Best for:** System services, production deployments, root access available

```bash
sudo ./install-system.sh
```

This will:
- Install Python packages via apt/dnf/yum
- Install system-wide (requires sudo)
- Make `camera-recorder` command available globally

**Supported distributions:**
- Debian 11, 12+
- Ubuntu 20.04, 22.04, 24.04+
- RHEL/CentOS 8, 9
- Fedora 35+

---

### Method 3: Manual Installation with pipx

**Best for:** User-level installations with pipx

```bash
# Install pipx if not available
sudo apt install pipx
pipx ensurepath

# Install camera recorder
pipx install -e .
```

---

### Method 4: System Packages Only (No pip)

**Best for:** Strict environments where pip is not allowed

```bash
# Install dependencies via package manager
sudo apt install python3-yaml python3-psutil python3-flask python3-werkzeug

# Manually copy module
sudo cp -r src/camera_recorder /usr/local/lib/python3.*/dist-packages/

# Create command wrapper
sudo tee /usr/local/bin/camera-recorder << 'EOF'
#!/usr/bin/env python3
from camera_recorder.main import main
if __name__ == '__main__':
    main()
EOF
sudo chmod +x /usr/local/bin/camera-recorder
```

---

## Troubleshooting

### "externally-managed-environment" Error

Modern Python installations (PEP 668) prevent pip from installing packages system-wide. Solutions:

1. **Use virtual environment** (recommended):
   ```bash
   ./install.sh
   ```

2. **Use system packages**:
   ```bash
   sudo ./install-system.sh
   ```

3. **Use pipx**:
   ```bash
   pipx install -e .
   ```

4. **Override protection** (not recommended):
   ```bash
   pip3 install --user --break-system-packages -e .
   ```

### Missing python3-venv

```bash
sudo apt install python3-venv python3-full
```

### Permission Denied

Don't run `install.sh` with sudo. It will create a venv for your user.

For system-wide installation, use `sudo ./install-system.sh` instead.

### Dependencies Not Found

If packages are missing:

**Debian/Ubuntu:**
```bash
sudo apt install python3-yaml python3-psutil python3-flask python3-werkzeug
```

**RHEL/Fedora:**
```bash
sudo dnf install python3-pyyaml python3-psutil python3-flask python3-werkzeug
```

---

## Verification

After installation, verify it works:

```bash
# Check version
camera-recorder --version

# Detect cameras
camera-recorder --detect

# Validate config
camera-recorder --validate
```

---

## Recommended Installation by Use Case

| Use Case | Recommended Method |
|----------|-------------------|
| Development / Testing | Virtual Environment (`./install.sh`) |
| Production Server | System-Wide (`sudo ./install-system.sh`) |
| Personal Use | Virtual Environment or pipx |
| Systemd Service | System-Wide or venv with updated service path |
| Docker Container | Virtual Environment in container |
| Multiple Versions | Virtual Environment (one per version) |

---

## Next Steps After Installation

1. **Configure cameras:**
   ```bash
   sudo mkdir -p /etc/camera-recorder
   sudo cp config.yaml.example /etc/camera-recorder/config.yaml
   sudo nano /etc/camera-recorder/config.yaml
   ```

2. **Detect cameras:**
   ```bash
   camera-recorder --detect
   ```

3. **Validate configuration:**
   ```bash
   camera-recorder --validate
   ```

4. **Test run:**
   ```bash
   camera-recorder
   # Press Ctrl+C to stop
   ```

5. **Install systemd service:**
   ```bash
   sudo cp systemd/camera-recorder-python.service /etc/systemd/system/
   # Edit if using venv
   sudo nano /etc/systemd/system/camera-recorder-python.service
   sudo systemctl daemon-reload
   sudo systemctl enable camera-recorder-python
   sudo systemctl start camera-recorder-python
   ```

6. **Access web interface:**
   ```
   http://localhost:8080
   http://<server-ip>:8080
   ```

---

## Uninstallation

### Virtual Environment Installation
```bash
rm -rf venv/
pip3 uninstall camera-recorder
```

### System-Wide Installation
```bash
sudo pip3 uninstall camera-recorder
# Or if installed via apt packages only
sudo rm -rf /usr/local/lib/python3.*/dist-packages/camera_recorder
sudo rm /usr/local/bin/camera-recorder
```

### pipx Installation
```bash
pipx uninstall camera-recorder
```

---

For more information, see:
- [PYTHON_README.md](PYTHON_README.md) - Python implementation guide
- [WEB_INTERFACE.md](WEB_INTERFACE.md) - Web interface documentation
- [QUICKSTART_WEB_INTERFACE.md](QUICKSTART_WEB_INTERFACE.md) - Quick start guide
