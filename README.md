# WoL Manu - Wake-on-LAN for macOS

<div align="center">
  <img src="AppIcon-Source.png" alt="WoL Manu Icon" width="128" height="128">
  
  **Professional Wake-on-LAN solution for macOS**
  
  [![macOS](https://img.shields.io/badge/macOS-26.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-green.svg)](https://developer.apple.com/xcode/swiftui/)
  [![Tests](https://img.shields.io/badge/Tests-Covered-brightgreen.svg)](#-testing)
  [![Security](https://img.shields.io/badge/Security-Hardened-red.svg)](#-security)
  [![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
</div>

## Overview

**WoL Manu** is a native macOS application developed in SwiftUI that allows you to remotely wake up network devices using Wake-on-LAN (WoL) Magic Packets. The application supports both local network and VPN-based remote wake-up with real-time device monitoring, and includes a network scanner and diagnostic tools (ping, traceroute, port scanner, DNS).

## ✨ Key Features

### Core Functionality
- 🖥️ **Native macOS Interface** - SwiftUI with Liquid Glass controls and a large one-click power button
- 🌐 **Dual Mode Operation** - Local broadcast or through a relay server reached over a VPN (e.g. WireGuard)
- 📡 **Real-time Monitoring** - Device status with 5-second ping intervals
- 🔄 **Advanced Retry System** - Exponential backoff + jitter for reliable transmission
- 🛡️ **Smart Fallback** - Falls back to local mode only when the Mac is on the target's network
- ✅ **Robust Validation** - Enhanced IP, MAC address, and configuration validation

### New in v1.5
- 🩺 **Connection Diagnostics** - Step-by-step check: route/VPN (incl. WireGuard status) → relay reachable → `/health` → `/wake` + API key → target device
- 🔎 **Network Scanner** - Finds devices on a subnet or an arbitrary IP range: IP, MAC, hostname (DNS, mDNS/Bonjour, NetBIOS), latency, open services, **vendor** (offline IEEE OUI database) and **device type** (router, PC, phone, VM, NAS, printer, TV…). One click sets a scanned device as the Wake-on-LAN target
- 🆕 **New-Device Alerts** - Remembers known MACs and sends a macOS notification when an unknown device appears; optional rescan every 5 minutes
- 🧰 **Network Tools** - Continuous ping with live chart and jitter, traceroute (ICMP like Windows `tracert`, or UDP), TCP port range scanner, DNS queries with side-by-side server comparison (detects ad-blocking DNS such as AdGuard/Pi-hole)
- ⚡ **Quick Access** - Menu bar extra with status and wake button; Shortcuts/Siri actions *"Encender equipo"* and *"Comprobar si el equipo está encendido"*
- 🔐 **Keychain** - The relay API key is stored in the macOS Keychain, never in `config.json` or exported files

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
- **macOS**: 26.0+ (Tahoe)
- **Architecture**: Apple Silicon (ARM64) or Intel (x86_64)
- **Network**: Local network access for device monitoring. macOS asks for the *Local Network* permission on first use; it is required to wake devices and to read MAC addresses in the scanner

### Installation

1. **Build** the app (see [Building from Source](#building-from-source)) or download it from the releases section
2. **Move to Applications folder** (recommended)
3. **First run**: Right-click → Open to bypass Gatekeeper if needed; allow *Local Network* access
4. **Configure device**: Enter device name, IP, and MAC address — or find it with the network scanner

### Basic Configuration

1. Launch **WoL Manu**
2. Click the **gear** button
3. Enter your device details:
   - **Device Name**: Descriptive name (e.g., "Gaming PC")
   - **IP Address**: Target device IP (e.g., 192.168.1.100)
   - **MAC Address**: Network adapter MAC (e.g., AA:BB:CC:DD:EE:FF)
4. Click **"Save"**

Alternatively open the **network scanner** (radio-waves button or ⌘⇧N) while the target is on, select it and click **"Use for Wake-on-LAN"**.

### Main Window and Shortcuts

| Control | Action |
|---|---|
| ⏻ power button | Send the Magic Packet (green when the device is online) |
| 🩺 | Connection diagnostics |
| ((•)) / ⌘⇧N | Network scanner |
| ⌘⇧T | Network tools (ping, traceroute, ports, DNS) |
| ⚙️ | Configuration |
| Menu bar ⏻ | Status and wake button without opening the window |

## 🏗️ Architecture

### Application Structure
```
WoL Manu/
├── WoL_ManuApp.swift            # App entry point: windows, menu bar extra, commands
├── ContentView.swift            # Main window (power button, status)
├── ConfigurationView.swift      # Settings sheet
├── ConfigurationModel.swift     # Configuration model and persistence (config.json + Keychain)
├── KeychainHelper.swift         # Keychain storage for the relay API key
├── WakeOnLANService.swift       # Magic Packet: local UDP or relay server (/wake, /wol)
├── PingService.swift            # Device monitoring
├── ConnectionDiagnostics.swift  # Step-by-step connection diagnostics
├── NetworkScanner.swift         # Subnet/range discovery, ARP (sysctl), names, ports, vendor, device type
├── NetworkScannerView.swift     # Scanner window
├── KnownDevicesStore.swift      # Known MACs and new-device notifications
├── NetworkTools.swift           # Ping, traceroute, port scanner and DNS engines
├── NetworkToolsView.swift       # Network tools window
├── MenuBarView.swift            # Menu bar extra
├── WoLAppIntents.swift          # Shortcuts / Siri actions
├── oui.txt                      # MAC vendor database (generated by scripts/update_oui.py)
└── Assets.xcassets/             # Application resources and icon
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
   - **API Key**: Authentication key configured on the server (stored in the macOS Keychain)
   - **Fallback**: Try local mode if the server fails (only used when the Mac is on the target's network — a broadcast never crosses the VPN tunnel)
4. Use the 🩺 **diagnostics** button to verify the whole path before you need it

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
  "apiKey": "",
  "serverPort": 5000,
  "fallbackLocal": true
}
```

Exports never contain the API key. An `apiKey` present in an imported file (or in an older `config.json`) is moved to the Keychain automatically.

## 🖧 Server Installation

For VPN mode, run a relay server inside the target network. The app works with both servers in this repository:

| Server | Endpoint | Notes |
|---|---|---|
| `wol_server.py` (recommended) | `POST /wake` | Standard library only, hardened, API key via `WOL_API_KEY_FILE` — see [SERVER.md](SERVER.md) |
| `wol-server/app.py` (Flask) | `POST /wol` | Legacy; the app falls back to `/wol` automatically |

### Recommended: `wol_server.py` with API key

```bash
# On the server
WOL_API_KEY_FILE=/etc/wol-server/api_key WOL_BROADCAST_IP=192.168.1.255 python3 wol_server.py
```

From the Mac, `scripts/deploy_relay_api_key.sh user@server` deploys `wol_server.py` to an existing systemd service, writes the key from the Keychain to `/etc/wol-server/api_key` (mode 600, sent over stdin), sets `WOL_BROADCAST_IP` to the server's /24 broadcast and verifies the result. Add `--harden-ssh` to disable SSH password logins (verified with `sshd -T`, automatic rollback on failure).

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
- **Xcode**: 26+ with macOS 26.0 SDK
- **Swift**: 6 toolchain (Swift 5 language mode, `MainActor` default isolation)
- **Frameworks**: SwiftUI, Charts, App Intents, Network, UserNotifications

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
- **Configuration**: `~/Projects/WoL Manu/config.json` (API key in the Keychain)
- **Known devices**: `~/Library/Application Support/WoL Manu/known_devices.json`
- **Application Bundle**: `WoL Manu.app`
- **Custom Icon**: `AppIcon-Source.png` (1024x1024)
- **MAC vendor database**: `python3 scripts/update_oui.py` regenerates `WoL Manu/oui.txt` from Wireshark's `manuf` list (derived from the IEEE registry)

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

# Swift client tests (20 tests)
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

**🧡 Swift Client Tests (20/20 passing):**
- ✅ MAC address parsing (colon, dash, no-separator formats; mixed separators rejected)
- ✅ IP range parsing and scan targets (from–to, last-octet shorthand, CIDR labels)
- ✅ MAC vendor lookup (/24, /28, /36 blocks) and device-type classification
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
- **API Key Authentication**: `wol_server.py` requires `X-API-Key` on `/wake` (constant-time comparison, 401 otherwise); the diagnostics warn when a relay accepts requests without a key
- **Keychain Storage**: The app keeps the API key in the macOS Keychain; it is never written to `config.json` or exports
- **Rate Limit Handling**: Intelligent 429 response processing
- **Private Network Only**: Restricted to RFC 1918 IP ranges
- **Firewall Integration**: UFW configuration for port access control
- **Comprehensive Logging**: All requests logged with timestamps and sources

#### Best Practices
- **API Keys**: Use cryptographically secure random generation (e.g. `openssl rand -hex 32`)
- **SSH**: Prefer key-only access to the relay host (`deploy_relay_api_key.sh --harden-ssh`)
- **Scanning**: Only scan networks and devices you own or are authorized to analyze
- **Network Security**: Implement firewall rules and VPN access
- **Configuration Files**: Validate JSON structure and content before import
- **Updates**: Regular security updates for all components
- **Monitoring**: Review logs for suspicious activity patterns

## 📚 Documentation

- **[Server Documentation](SERVER.md)** - `wol_server.py` API, security and API key setup
- **[WireGuard Setup](wireguard_wol_setup.md)** - Wake-on-LAN through a WireGuard VPN
- **[Development Guide](WARP.md)** - Technical documentation for developers
- **[Changelog](CHANGELOG.md)**
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
- Run the 🩺 **diagnostics**: it shows which step fails (no route / VPN down, server unreachable, wrong endpoint, API key rejected)
- Verify server is running: `sudo systemctl status wol-server`
- Check firewall allows port 5000
- Validate API key in configuration

**Scanner shows no MAC addresses:**
- Grant *Local Network* access in System Settings → Privacy & Security → Local Network
- MACs are only visible on the local network: ARP does not cross a VPN tunnel

**Traceroute stops before the destination:**
- Use **ICMP** (default). Many firewalls — e.g. Windows hosts — drop the UDP probes macOS `traceroute` uses by default

**Configuration import fails:**
- Verify JSON file format is valid
- Check all required fields are present
- Ensure IP and MAC address formats are correct

## 📊 Version History

- **v1.5** - 🧰 **Network tools & VPN fixes**
  - ✅ Fixed VPN wake against `wol_server.py` (health status, `/wake` endpoint)
  - ✅ Redesigned main window and new icon
  - ✅ Network scanner with vendor/device type and new-device alerts
  - ✅ Ping, traceroute, port scanner and DNS tools
  - ✅ Connection diagnostics, menu bar extra, Shortcuts/Siri actions
  - ✅ API key in the Keychain; server-side API key enforcement

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
- **Wireshark `manuf` / IEEE OUI registry** - MAC vendor data

---

<div align="center">
  <p><strong>WoL Manu</strong> - Wake up your devices remotely with style! 🚀</p>
</div>