# WoL Manu - macOS Wake-on-LAN Application

A native macOS application built with SwiftUI for sending Wake-on-LAN packets to remote devices, with support for both local and VPN server modes.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-3.0+-green.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- 🖥️ **Native macOS Application** - Built with SwiftUI for seamless macOS integration
- 🌐 **Dual Mode Operation** - Local UDP broadcast and remote HTTP server support
- 📡 **Real-time Monitoring** - Device status monitoring with ping every 5 seconds
- 🔄 **Intelligent Retry System** - Exponential backoff with up to 3 retry attempts
- 🛡️ **Fallback Support** - Automatic fallback from VPN to local mode
- 🔍 **Input Validation** - IP address, MAC address, and configuration validation
- 📊 **Activity Logging** - Keep track of the last 10 Wake-on-LAN attempts
- 🔐 **Secure API Server** - Optional Flask server with API key authentication

## Screenshots

*Note: Add screenshots here when available*

## Architecture

### Client Application (macOS)
- **Language**: Swift 5.7+
- **Framework**: SwiftUI 3.0+
- **Architecture**: MVVM with Combine for reactive programming
- **Minimum macOS**: 12.0 (Monterey)

### Server Component (Optional)
- **Language**: Python 3.7+
- **Framework**: Flask with secure API endpoints
- **Supported OS**: Debian 12+, Ubuntu 20.04+
- **Features**: Health checks, request logging, API key authentication

## Quick Start

### 1. Download & Install

```bash
# Clone the repository
git clone https://github.com/username/WoL-Manu.git
cd WoL-Manu

# Build the macOS application
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build

# Install to Applications folder
sudo cp -R "Build/Products/Debug/WoL Manu.app" /Applications/
```

### 2. Configure Your Device

1. Launch **WoL Manu**
2. Click **"Configuration"**
3. Enter your device details:
   - **Device Name**: Descriptive name
   - **IP Address**: Target device IP (e.g., 192.168.1.100)
   - **MAC Address**: Target device MAC (e.g., 00:11:22:33:44:55)

### 3. Enable Wake-on-LAN on Target Device

#### Windows
- Device Manager → Network Adapters → [Your Ethernet Adapter]
- Properties → Advanced → "Wake on Magic Packet" → Enable
- Properties → Power Management → ✅ "Allow this device to wake the computer"

#### macOS
```bash
sudo pmset -a womp 1
```

#### Linux
```bash
sudo ethtool -s eth0 wol g
```

## VPN Server Setup (Optional)

For remote Wake-on-LAN through VPN or external networks:

### Automatic Installation
```bash
cd wol-server
sudo ./install.sh
```

### Manual Installation
```bash
# Install dependencies
sudo apt update
sudo apt install python3 python3-pip python3-venv wakeonlan

# Create service user
sudo useradd --system wol-server

# Install application
sudo cp app.py requirements.txt /opt/wol-server/
cd /opt/wol-server
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt

# Configure systemd service
sudo systemctl enable wol-server
sudo systemctl start wol-server
```

## Usage

### Local Mode
1. Configure device details
2. Uncheck **"Enable VPN Mode"**
3. Click **"Wake Up"**

### VPN Mode
1. Install and configure the WoL server
2. Check **"Enable VPN Mode"**
3. Enter server details:
   - **Server IP**: Your server's IP address
   - **Port**: 5000 (default)
   - **API Key**: Generated during server installation
4. Click **"Wake Up"**

## Project Structure

```
WoL Manu/
├── WoL Manu/                    # Swift application source
│   ├── WoL_ManuApp.swift       # Application entry point
│   ├── ContentView.swift       # Main interface
│   ├── ConfigurationView.swift # Settings modal
│   ├── ConfigurationModel.swift# Data models & persistence
│   ├── WakeOnLANService.swift  # Core WoL functionality
│   └── PingService.swift       # Device monitoring
├── wol-server/                  # Python server components
│   ├── app.py                  # Flask application
│   ├── requirements.txt        # Python dependencies
│   ├── install.sh             # Automated installer
│   └── README.md              # Server documentation
└── Documentation/               # Guides and examples
    ├── INSTALLATION_GUIDE.md
    └── configuration-example.txt
```

## API Reference

The server exposes the following endpoints:

### Health Check
```http
GET /health
```
Response: `{"status": "ok", "timestamp": "...", "server": "wol-server", "version": "1.0"}`

### Wake-on-LAN
```http
POST /wol
Content-Type: application/json
X-API-Key: your-api-key

{
    "mac": "00:11:22:33:44:55",
    "ip": "192.168.1.100",
    "name": "My Device"
}
```

### Server Status
```http
GET /status
X-API-Key: your-api-key
```

## Configuration

### Application Settings
Configuration is stored in: `~/Projects/WoL Manu/config.json`

```json
{
    "deviceName": "My Device",
    "ipAddress": "192.168.1.100",
    "macAddress": "00:11:22:33:44:55",
    "vpnMode": false,
    "serverIP": "192.168.1.200",
    "serverPort": 5000,
    "apiKey": "",
    "fallbackLocal": true
}
```

### Server Settings
Server configuration: `/etc/wol-server/config.json`

```json
{
    "api_key": "generated-32-byte-key",
    "port": 5000,
    "allowed_networks": ["192.168.0.0/16", "10.0.0.0/8"],
    "log_level": "INFO"
}
```

## Development

### Prerequisites
- **Xcode 15.0+**
- **Swift 5.7+**
- **macOS 12.0+** for testing

### Building
```bash
# Debug build
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build

# Release build  
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" -configuration Release build
```

### Testing
```bash
# Run application tests
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" test

# Test Wake-on-LAN functionality
python3 test_wol.py
```

## Troubleshooting

### Common Issues

**Device doesn't wake up:**
- Ensure Wake-on-LAN is enabled in BIOS/UEFI
- Confirm device is connected via Ethernet (not WiFi)
- Verify MAC address is correct
- Test with device recently shut down (not deep sleep)

**VPN connection errors:**
- Check server is running: `sudo systemctl status wol-server`
- Verify server IP is accessible from your Mac
- Confirm API key is correct
- Review server logs: `sudo journalctl -u wol-server -f`

**Network connectivity:**
```bash
# Test connectivity
ping 192.168.1.100

# Test server
curl http://192.168.1.200:5000/health

# Send WoL manually
wakeonlan 00:11:22:33:44:55
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure your code follows the existing style and includes appropriate tests.

## Security

- Server API keys are generated with 256-bit entropy
- Network access is restricted to private IP ranges by default
- All server communications use input validation and sanitization
- Logs are configured with appropriate rotation and retention policies

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Wake-on-LAN protocol implementation based on standard Magic Packet specification
- SwiftUI interface design following Apple Human Interface Guidelines
- Server security practices following OWASP recommendations

---

**Developed with ❤️ for the macOS community**

*For detailed installation instructions, see [INSTALLATION_GUIDE.md](Documentation/INSTALLATION_GUIDE.md)*