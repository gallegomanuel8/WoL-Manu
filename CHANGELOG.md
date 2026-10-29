# Changelog

All notable changes to the WoL Manu project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-10-29 🧰 Network Tools & VPN Fixes

### 🔧 Fixed
- **[CRITICAL]** Wake over VPN never reached the server's wake step: the relay (`wol_server.py`) answers `/health` with `"healthy"` and exposes `POST /wake`, while the app expected `"ok"` and called `/wol`. The app now accepts both and falls back to `/wol` for the legacy Flask server
- Local fallback is only attempted when the Mac is on the target's /24 (a broadcast never crosses a VPN tunnel)
- Processing indicator stayed off while the VPN request was still running
- 5xx retries stopped at attempt 3 of 4
- MAC parsing now rejects mixed separators (`00:1B-63:…`)

### ✨ Added
- **Network scanner** (⌘⇧N): local interface or arbitrary IP range (from–to); IP, MAC (ARP via `sysctl`), hostname (reverse DNS, mDNS/Bonjour, NetBIOS), latency, open services, vendor and device type; inspector with clickable services and "Use for Wake-on-LAN"
- **MAC vendor database** (`oui.txt`, ~58k IEEE MA-L/MA-M/MA-S prefixes, offline) and `scripts/update_oui.py`
- **New-device alerts**: known MACs persisted, NUEVO badge and macOS notification for unknown devices, optional rescan every 5 minutes
- **Network tools** (⌘⇧T): continuous ping with chart, loss and jitter; traceroute (ICMP by default, UDP optional) with per-hop names and destination check; TCP port range scanner (batched non-blocking connects); DNS queries and server comparison with block detection
- **Connection diagnostics**: route/VPN (WireGuard status), relay TCP, `/health`, `/wake` + API key, target ping
- **Menu bar extra** and **Shortcuts/Siri** actions (wake device, check if on)
- `scripts/deploy_relay_api_key.sh` to deploy the relay with an API key and optionally disable SSH password logins

### 🔒 Security
- Relay API key stored in the macOS Keychain (migrated from `config.json`, excluded from exports)
- `wol_server.py` enforces `X-API-Key` on `/wake` (`WOL_API_KEY_FILE` / `WOL_API_KEY`, constant-time comparison)
- `NSLocalNetworkUsageDescription` declared so macOS can ask for Local Network access

### 🎨 Changed
- Redesigned main window (large power button, Liquid Glass controls, status pill, result banner) and configuration form
- New app icon
- Requires macOS 26

## [1.4.0] - 2024-09-30 🚀 Major Stability & Security Update

### 🔧 Fixed
- **[CRITICAL]** Fixed UDP transmission reliability by adding 300ms delay before socket closure
  - Ensures complete Magic Packet delivery
  - Prevents premature connection termination
  - Improves wake-up success rate significantly

- **[CRITICAL]** Enhanced broadcast address handling
  - Corrected UDP socket configuration for proper broadcast
  - Fixed Magic Packet destination addressing
  - Improved local network device discovery

### ✨ Added
- **Comprehensive Unit Test Suite** (23 tests total)
  - Python server tests (15/15 passing) - MAC/IP validation, DoS protection, Magic Packet construction
  - Swift client tests (8/9 passing) - MAC parsing, packet building, edge cases
  - Automated test runner script (`run_all_tests.sh`) with colorized output
  - Performance benchmarks (1000+ operations/second)

- **Advanced Network Retry Logic**
  - Exponential backoff with jitter to prevent thundering herd
  - Intelligent rate limiting (429 error) handling
  - Increased retry attempts (3→4) with smart delay calculation
  - Enhanced error classification and recovery

- **Enhanced Input Validation & Security**
  - Strict MAC address validation (rejects 00:00:00:00:00:00, FF:FF:FF:FF:FF:FF)
  - IPv4 validation using `socket.inet_aton()` for strict checking
  - DoS protection with input length limits (MAC ≤20 chars, IP ≤15 chars, Name ≤50 chars)
  - Leading zero rejection in IP addresses
  - Support for multiple MAC formats (colon, dash, no-separator)

### 🔒 Security
- **Server Hardening**
  - Systemd service isolation with restricted syscalls
  - Blocked access to kernel modules (`NoNewPrivileges=true`)
  - Control group protection (`ProtectControlGroups=true`)
  - Non-privileged user execution with minimal permissions
  - File system isolation (`ProtectHome=true`, `ProtectSystem=strict`)

- **Enhanced File Permissions**
  - Configuration files locked to 600 (owner-only access)
  - Application directory restricted to wol-server user
  - Log files with proper rotation and access control

### 🚀 Performance
- **URLSession Optimization**
  - Increased timeouts (5s→10s for requests, 15s→25s for resources)
  - Connection reuse and keep-alive optimization
  - Cellular network restriction for reliability
  - Custom User-Agent for better server identification

- **Network Stack Improvements**
  - Optimized connection pooling
  - Better timeout handling in various network conditions
  - Improved error propagation and logging

### 📊 Monitoring & Logging
- **Comprehensive Activity Logging**
  - Detailed HTTP request/response logging
  - Network error classification and reporting
  - Retry attempt tracking with timestamps
  - Performance metrics collection

- **Enhanced Debug Information**
  - Verbose logging modes for troubleshooting
  - Network state reporting
  - Connection failure analysis

### 🛠️ Developer Experience
- **Testing Infrastructure**
  - Automated test execution with single command
  - Test result aggregation and reporting
  - Performance regression detection
  - Continuous integration readiness

- **Code Quality Improvements**
  - Function visibility optimization for testing (internal scope)
  - Enhanced error handling and propagation
  - Better separation of concerns
  - Documentation updates

### 📚 Documentation
- Updated README.md with comprehensive feature list
- Enhanced security documentation
- Complete testing guide
- Troubleshooting section improvements

---

## [1.3.0] - 2024-09-15 ✨ Configuration Management

### ✨ Added
- **Import/Export Configuration**
  - JSON-based configuration file format
  - Easy device setup sharing between installations
  - Configuration validation and error handling
  - Backup and restore functionality

### 🔧 Improved
- Enhanced configuration UI with import/export buttons
- Better error messages for configuration validation
- Improved JSON parsing with comprehensive error handling

---

## [1.2.0] - 2024-09-01 🎨 Visual Identity

### ✨ Added
- **Custom Application Icon**
  - Professional 1024x1024 source icon (`AppIcon-Source.png`)
  - Generated app icon bundle for all macOS sizes
  - Native macOS application appearance

### 🔧 Improved
- Polished user interface elements
- Better visual feedback for button states
- Enhanced application branding

---

## [1.1.0] - 2024-08-15 🌐 VPN Mode Support

### ✨ Added
- **VPN Mode Operation**
  - Remote wake-up through intermediate server
  - Python Flask-based WoL server
  - API key authentication
  - Automatic installation script for server

- **Smart Fallback System**
  - Auto-detection of server availability
  - Graceful degradation to local mode
  - Health check implementation

### 🔧 Improved
- Enhanced network error handling
- Better connection state management
- Improved user feedback for network operations

---

## [1.0.0] - 2024-08-01 🎉 Initial Release

### ✨ Added
- **Core Wake-on-LAN Functionality**
  - Magic Packet transmission over UDP
  - Local network broadcast support
  - MAC address validation and parsing

- **Native macOS Application**
  - SwiftUI-based user interface
  - macOS 12.0+ compatibility
  - Native macOS design patterns

- **Device Configuration**
  - Device name, IP address, and MAC address storage
  - JSON-based configuration persistence
  - Input validation for network parameters

- **Real-time Monitoring**
  - Device status checking via ICMP ping
  - 5-second monitoring intervals
  - Visual status indicators

- **Activity Logging**
  - Last 10 Wake-on-LAN attempts tracking
  - Success/failure status recording
  - Timestamp and method logging

---

## Technical Notes

### Compatibility
- **macOS**: 12.0+ (Monterey, Ventura, Sonoma, Sequoia)
- **Architecture**: Apple Silicon (ARM64) and Intel (x86_64)
- **Swift**: 5.7+
- **Python**: 3.8+ (server component)

### Dependencies
- **SwiftUI**: Native framework for UI
- **Combine**: Reactive programming
- **Network**: Low-level networking
- **Python Flask**: Server API framework
- **systemd**: Linux service management

### Build Requirements
- **Xcode**: 15.0+
- **macOS SDK**: 26.0+
- **Command Line Tools**: Latest version

---

## Migration Guide

### Upgrading from v1.3 to v1.4
1. **Client Update**: Replace application binary
2. **Server Update**: Run `sudo ./install.sh` to update server with security enhancements  
3. **Configuration**: Existing configurations are fully compatible
4. **Testing**: Run `./run_all_tests.sh` to verify installation

### Breaking Changes
- None. All versions are backward compatible.

### Deprecated Features
- None. All features from previous versions remain supported.

---

## Contributors

- **Manu** - Main developer and maintainer
- **WARP AI** - Development assistance and code review

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.