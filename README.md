# WoL Manu - Wake-on-LAN for macOS

<div align="center">
  <img src="AppIcon-Source.png" alt="WoL Manu Icon" width="128" height="128">
  
  **Professional Wake-on-LAN solution for macOS**
  
  [![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-green.svg)](https://developer.apple.com/xcode/swiftui/)
  [![Tests](https://img.shields.io/badge/Tests-Covered-brightgreen.svg)](#-testing)
  [![Security](https://img.shields.io/badge/Security-Hardened-red.svg)](#-security)
  [![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
</div>

## Overview

**WoL Manu** is a native macOS application developed in SwiftUI that allows you to remotely wake up network devices using Wake-on-LAN (WoL) Magic Packets. The application supports both local network and VPN-based remote wake-up with real-time device monitoring.

## ✨ Key Features

### Core Functionality
- 🖥️ **Native macOS Interface** - Clean SwiftUI design with macOS integration
- 🌐 **Dual Mode Operation** - Local network and VPN server support  
- 📡 **Real-time Monitoring** - Device status with 5-second ping intervals
- 🔄 **Advanced Retry System** - Exponential backoff + jitter for reliable transmission
- 🛡️ **Smart Fallback** - Auto-fallback from VPN to local mode on failure
- ✅ **Robust Validation** - Enhanced IP, MAC address, and configuration validation

### Enhanced Reliability (v1.4)
- 🔧 **UDP Transmission Fix** - 300ms delay ensures complete packet delivery
- 🚀 **Optimized URLSession** - Improved timeouts and connection handling
- 🔄 **Rate Limit Protection** - Intelligent handling of server rate limiting (429 errors)
- 📊 **Comprehensive Logging** - Detailed activity tracking and error reporting

### Developer & Security Features
- 🧪 **Unit Test Coverage** - Comprehensive test suite for both client and server
- 🔒 **Hardened Security** - Server isolation, input sanitization, DoS protection  
- 📁 **Import/Export** - Easy configuration sharing and backup
- 🎨 **Professional Design** - Custom icon and polished interface
- 🔐 **Secure API** - Authenticated server communication with API keys

## 🚀 Quick Start

### Requirements
- **macOS**: 12.0+ (Monterey or higher)
- **Architecture**: Apple Silicon (ARM64) or Intel (x86_64)
- **Network**: Local network access for device monitoring

### Installation

1. **Download the compiled application** from the releases section
2. **Move to Applications folder** (optional but recommended)
3. **First run**: Right-click → Open to bypass Gatekeeper if needed
4. **Configure device**: Enter device name, IP, and MAC address

### Basic Configuration

1. Launch **WoL Manu**
2. Click **"Configuration"** button
3. Enter your device details:
   - **Device Name**: Descriptive name (e.g., "Gaming PC")
   - **IP Address**: Target device IP (e.g., 192.168.1.100)
   - **MAC Address**: Network adapter MAC (e.g., AA:BB:CC:DD:EE:FF)
4. Click **"Save"**

## 🏗️ Architecture

### Application Structure
```
WoL Manu/
├── WoL_ManuApp.swift          # Main application entry point
├── ContentView.swift          # Primary user interface
├── ConfigurationView.swift    # Settings and configuration modal
├── ConfigurationModel.swift   # Data models and persistence
├── WakeOnLANService.swift     # UDP Magic Packet transmission
├── PingService.swift          # Device monitoring service
└── Assets.xcassets/          # Application resources and icon
```

### Design Patterns
- **MVVM Architecture** - Clean separation of concerns
- **Reactive Programming** - Combine framework for data flow
- **Service Layer** - Modular network and persistence services
- **SwiftUI Declarative UI** - Native macOS interface patterns

## ⚙️ Advanced Features

### VPN Mode Configuration
Enable remote wake-up through an intermediary server:

1. Install the WoL server on your network (see [Server Installation](#server-installation))
2. In app configuration, enable **"VPN Mode"**
3. Configure server settings:
   - **Server IP**: VPN server address
   - **Port**: Server port (default: 5000)
   - **API Key**: Authentication key from server installation
   - **Fallback**: Enable local mode if server fails

### Import/Export Configurations

**Export Configuration:**
- Open Configuration window → Click **"Export"** → Save JSON file

**Import Configuration:**
- Open Configuration window → Click **"Import"** → Select JSON file

**Example Configuration File:**
```json
{
  "deviceName": "Office Gaming PC",
  "ipAddress": "192.168.1.150",
  "macAddress": "AA:BB:CC:DD:EE:FF",
  "vpnMode": true,
  "serverIP": "YOUR_SERVER_IP",
  "apiKey": "your-api-key-here",
  "serverPort": 5000,
  "fallbackLocal": true
}
```

## 🖧 Server Installation

For VPN mode, install the companion server on your network:

### Automatic Installation (Debian/Ubuntu)
```bash
# Clone repository
git clone <repository-url>
cd WoL-Manu/wol-server

# Run installer
sudo ./install.sh
```

### Manual Installation
```bash
# Install dependencies
sudo apt update
sudo apt install python3 python3-pip python3-venv wakeonlan openssl

# Create service user and directories
sudo groupadd --system wol-server
sudo useradd --system --gid wol-server --home-dir /opt/wol-server wol-server
sudo mkdir -p /opt/wol-server /etc/wol-server

# Install application
sudo cp app.py requirements.txt /opt/wol-server/
cd /opt/wol-server
sudo -u wol-server python3 -m venv venv
sudo -u wol-server venv/bin/pip install -r requirements.txt

# Generate configuration and start service
# (See complete installation guide for details)
```

## 🔧 Device Configuration

### Target Device Setup
Ensure your target device supports Wake-on-LAN:

**Windows:**
- Enable WoL in BIOS/UEFI settings
- Configure network adapter: "Allow this device to wake the computer"
- Enable "Wake on Magic Packet" in adapter advanced settings

**macOS:**
- System Preferences → Energy Saver → "Wake for network access"
- Or via Terminal: `sudo pmset -a womp 1`

**Linux:**
- Install ethtool: `sudo apt install ethtool`
- Enable WoL: `sudo ethtool -s eth0 wol g`
- Make persistent with systemd service

## 🛠️ Development

### Build Requirements
- **Xcode**: 15.0+ with macOS 26.0 SDK
- **Swift**: 5.7+
- **SwiftUI**: Native framework

### Building from Source
```bash
# Clone repository
git clone <repository-url>
cd WoL-Manu

# Open in Xcode
open "WoL Manu.xcodeproj"

# Or build from command line
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build

# Run the application
./run_app.sh
```

### Project Structure
- **Configuration**: `~/Projects/WoL Manu/config.json`
- **Application Bundle**: `WoL Manu.app`
- **Custom Icon**: Generated from `AppIcon-Source.png` (1024x1024)

## 🧪 Testing

### Comprehensive Test Suite (v1.4)

WoL Manu now includes a complete unit test coverage for both client and server components:

#### Automated Test Execution
```bash
# Run ALL tests with automated script
./run_all_tests.sh

# Individual test suites:
# Python server tests (15 tests)
cd wol-server && python3 test_validations.py

# Swift client tests (9 tests)  
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" test
```

#### Test Coverage

**🐍 Python Server Tests (15/15 passing):**
- ✅ MAC address validation (multiple formats)
- ✅ IP address validation (IPv4 strict validation)
- ✅ Magic packet construction (102-byte packets)
- ✅ DoS protection (length limits, invalid input rejection)
- ✅ Integration testing (complete request flow)
- ✅ Edge case handling (malformed inputs)

**🧡 Swift Client Tests (8/9 passing):**
- ✅ MAC address parsing (colon, dash, no-separator formats)
- ✅ Magic packet building (6 bytes 0xFF + 16x MAC)
- ✅ Input validation (invalid MAC rejection)
- ✅ Integration flow (MAC parsing + packet construction)
- ✅ Performance benchmarks (1000+ operations/second)
- ✅ Edge cases (broadcast MAC, zero MAC handling)

#### Legacy Testing
```bash
# Legacy Wake-on-LAN functionality test
python3 test_wol.py

# Comprehensive device testing
python3 test_target_device.py

# VPN server integration
python3 test_wol_via_vpn.py
```

### Manual Testing
1. **Local Mode**: Test direct UDP packet transmission with 300ms delay
2. **VPN Mode**: Verify server-mediated wake-up with retry logic
3. **Import/Export**: Test configuration file handling and validation
4. **Monitoring**: Verify real-time device status updates (5s intervals)
5. **Error Handling**: Test network failures and automatic fallback

## 🔒 Security

### Enhanced Security Framework (v1.4)

#### Input Validation & DoS Protection
- **✅ Strict MAC Validation**: Rejects common invalid MACs (00:00:00:00:00:00, FF:FF:FF:FF:FF:FF)
- **✅ IP Address Sanitization**: Uses `socket.inet_aton()` for strict IPv4 validation
- **✅ Length Limits**: Prevents DoS attacks with input size restrictions
- **✅ Format Enforcement**: Supports colon, dash, and no-separator MAC formats
- **✅ Leading Zero Rejection**: Blocks potentially malicious IP formats

#### Server Hardening
- **✅ Systemd Security**: Process isolation with restricted syscalls
- **✅ Non-Privileged User**: Dedicated `wol-server` user with minimal permissions
- **✅ File Permissions**: Configuration files locked to 600 (owner-only)
- **✅ Directory Isolation**: Application runs in `/opt/wol-server` with restricted access
- **✅ Kernel Modules**: Blocked access to loadable kernel modules
- **✅ Control Groups**: Process resource limits and isolation

#### Network Security
- **API Key Authentication**: Strong random key generation and validation
- **Rate Limit Handling**: Intelligent 429 response processing
- **Private Network Only**: Restricted to RFC 1918 IP ranges
- **Firewall Integration**: UFW configuration for port access control
- **Comprehensive Logging**: All requests logged with timestamps and sources

#### Best Practices
- **API Keys**: Use cryptographically secure random generation
- **Network Security**: Implement firewall rules and VPN access
- **Configuration Files**: Validate JSON structure and content before import
- **Updates**: Regular security updates for all components
- **Monitoring**: Review logs for suspicious activity patterns

## 📚 Documentation

- **[Complete Installation Guide (English)](INSTALLATION_GUIDE_COMPLETE_EN.md)**
- **[Guía de Instalación Completa (Español)](GUIA_INSTALACION_COMPLETA.md)**
- **[Development Guide](WARP.md)** - Technical documentation for developers
- **[API Documentation](wol-server/)** - Server API endpoints and usage

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** your changes (`git commit -m 'Add AmazingFeature'`)
4. **Push** to the branch (`git push origin feature/AmazingFeature`)
5. **Open** a Pull Request

### Development Setup
```bash
# Clone your fork
git clone https://github.com/yourusername/WoL-Manu.git
cd WoL-Manu

# Create development branch
git checkout -b feature/your-feature-name

# Make changes and test
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build
./run_app.sh
```

## 📝 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## 🐛 Troubleshooting

### Common Issues

**Application won't start:**
```bash
# Remove quarantine attribute
sudo xattr -rd com.apple.quarantine "/Applications/WoL Manu.app"
```

**Device won't wake up:**
- Verify Wake-on-LAN is enabled in device BIOS
- Ensure Ethernet connection (not WiFi)
- Check IP and MAC addresses are correct
- Test with local mode first

**Server connection fails:**
- Verify server is running: `sudo systemctl status wol-server`
- Check firewall allows port 5000
- Validate API key in configuration

**Configuration import fails:**
- Verify JSON file format is valid
- Check all required fields are present
- Ensure IP and MAC address formats are correct

## 📊 Version History

- **v1.4** - 🚀 **Major Stability & Security Update**
  - ✅ Critical UDP transmission fix (300ms delay)
  - ✅ Advanced retry logic with exponential backoff + jitter
  - ✅ Comprehensive unit test suite (23 tests total)
  - ✅ Enhanced input validation and DoS protection
  - ✅ Server security hardening with systemd isolation
  - ✅ Rate limiting and error handling improvements
  - ✅ URLSession optimization for better reliability

- **v1.3** - Import/Export configuration functionality
- **v1.2** - Custom application icon and improved UI
- **v1.1** - VPN server support with automatic fallback
- **v1.0** - Initial release with local Wake-on-LAN

## 🙏 Acknowledgments

- **Wake-on-LAN Protocol** - AMD's Magic Packet standard
- **SwiftUI Framework** - Apple's declarative UI framework
- **Combine Framework** - Reactive programming support
- **Python Flask** - Server-side API implementation

---

<div align="center">
  <p><strong>WoL Manu</strong> - Wake up your devices remotely with style! 🚀</p>
</div>