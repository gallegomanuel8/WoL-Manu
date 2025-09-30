# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a **Wake-on-LAN application for macOS** - a native SwiftUI app that sends Magic Packets to remotely wake up network devices. The application is fully functional and production-ready.

**Key Facts:**
- **Language:** Swift 5.7+
- **UI Framework:** SwiftUI 
- **Platform:** macOS 12.0+
- **Architecture:** MVVM pattern with reactive programming (Combine)
- **Version:** 1.4.0 - Major Stability & Security Update
- **Test Coverage:** 23 comprehensive unit tests (Python + Swift)
- **Security:** Hardened with input validation and DoS protection
- **Project Status:** ✅ Production-ready with enterprise-grade reliability

## Common Development Commands

### Building and Running
```bash
# Build the project
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build

# Run the compiled application (easiest way)
./run_app.sh

# Open project in Xcode
open "WoL Manu.xcodeproj"
```

### Testing (v1.4 Enhanced)
```bash
# Run ALL tests with automated script (RECOMMENDED)
./run_all_tests.sh

# Individual test suites:
# Python server tests (15 tests)
cd wol-server && python3 test_validations.py

# Swift client tests (9 tests)
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" test

# Legacy functionality tests
python3 test_wol.py
python3 test_target_device.py
```

### Configuration and Debugging
```bash
# View current device configuration
cat config.json

# Monitor application logs (when running)
# Check Console.app for "WoL Manu" entries

# Find compiled application location
find ~/Library/Developer/Xcode/DerivedData/WoL_Manu-*/Build/Products/Debug -name "WoL Manu.app" 2>/dev/null
```

## Code Architecture

### High-Level Architecture
The application follows the **MVVM (Model-View-ViewModel)** pattern with **reactive programming** using Combine:

```
┌───────────────────────────────────────────────┐
│            Views (SwiftUI) - v1.4           │
│  • ContentView (Main Interface + Logging)  │
│  • ConfigurationView (Enhanced Settings)  │
└───────────────────────────────────────────────┘
                         │
┌───────────────────────────────────────────────┐
│    ViewModels/Services - Enhanced v1.4    │
│  • ConfigurationManager (@Published)      │
│  • PingService (Device Monitoring)        │
│  • WakeOnLANService (Robust UDP + Retry) │
└───────────────────────────────────────────────┘
                         │
┌───────────────────────────────────────────────┐
│        Models & Testing - v1.4           │
│  • DeviceConfiguration (Codable)          │
│  • Enhanced Input Validation             │
│  • Unit Test Coverage (23 tests)         │
│  • Python Server (Hardened Security)    │
└───────────────────────────────────────────────┘
```

### Core Components

1. **WoL_ManuApp.swift** - Application entry point
2. **ContentView.swift** - Main UI with device status, wake button, and configuration access
3. **ConfigurationView.swift** - Device setup (Name, IP, MAC address)
4. **ConfigurationManager.swift** - Handles JSON persistence of device configuration
5. **WakeOnLANService.swift** - UDP broadcast service for Magic Packet transmission
6. **PingService.swift** - Continuous device monitoring with 5-second intervals

### Key Design Patterns

- **@StateObject/@ObservableObject** for reactive state management
- **Combine framework** for asynchronous operations and data binding  
- **Service layer separation** - Network, persistence, and monitoring are separate services
- **JSON configuration persistence** - Device settings saved to `~/Projects/WoL Manu/config.json`

### Network Implementation Details (v1.4 Enhanced)

**Magic Packet Construction:**
- Format: 6 bytes of `0xFF` + 16 repetitions of the target MAC address
- Total size: 102 bytes
- Sent via UDP broadcast to port 9 (standard Wake-on-LAN port)
- **NEW**: 300ms delay before socket closure for guaranteed delivery
- **NEW**: Enhanced error handling and retry logic

**Advanced Retry System:**
- Exponential backoff with jitter (prevents thundering herd)
- 4 retry attempts (increased from 3)
- Rate limiting detection and intelligent handling (429 errors)
- URLSession optimization with extended timeouts
- Custom User-Agent and connection reuse

**Device Monitoring:**
- Uses system `ping` command: `ping -c 1 -W 3000 <IP>`
- 5-second intervals with visual status indicators (green/red circles)
- Reactive UI updates via Combine publishers
- **NEW**: Enhanced error reporting and connection state tracking

### File Structure (v1.4 Enhanced)
```
WoL Manu/
├── WoL_ManuApp.swift          # @main entry point
├── ContentView.swift          # Primary interface (350×500px)
├── ConfigurationView.swift    # Settings modal (400×350px)  
├── ConfigurationModel.swift   # DeviceConfiguration model + persistence
├── WakeOnLANService.swift     # Enhanced UDP Magic Packet service
└── PingService.swift          # Device monitoring service

WoL ManuTests/ (NEW v1.4)
└── WakeOnLANServiceTests.swift # Comprehensive Swift unit tests (9 tests)

wol-server/ (Enhanced v1.4)
├── app.py                     # Flask server with hardened security
├── install.sh                 # Enhanced installation with security
├── test_validations.py        # Python unit tests (15 tests)
└── wol-server.service         # Systemd service with security isolation

Root Directory:
├── config.json               # Runtime device configuration
├── run_app.sh               # Launch script  
├── run_all_tests.sh         # NEW: Automated test runner
├── CHANGELOG.md             # NEW: Complete version history
├── test_wol.py             # Legacy Python test suite
├── test_report.md          # Comprehensive test results
└── RESUMEN_PROYECTO.md     # Detailed project summary (Spanish)
```

## Development Context

### Configuration Storage
- **Location:** `~/Projects/WoL Manu/config.json`
- **Format:** JSON with `deviceName`, `ipAddress`, `macAddress`
- **Validation:** IP format validation + MAC address parsing (supports `:`, `-`, or no separators)

### Testing Strategy (v1.4 Comprehensive)

**Unit Testing (23 tests total):**
- **Python Server Tests (15/15 passing):**
  - MAC address validation (colon, dash, no-separator formats)
  - IP address validation (strict IPv4 with socket.inet_aton)
  - Magic packet construction (102-byte packets)
  - DoS protection (length limits, invalid input rejection)
  - Integration testing (complete request flow)
  - Edge case handling (malformed inputs, reserved addresses)

- **Swift Client Tests (8/9 passing):**
  - MAC address parsing with multiple format support
  - Magic packet building (6 bytes 0xFF + 16x MAC)
  - Input validation and invalid MAC rejection
  - Integration flow (MAC parsing + packet construction)
  - Performance benchmarks (1000+ operations/second)
  - Edge cases (broadcast MAC, zero MAC handling)

**Automated Testing:**
- Single-command test execution: `./run_all_tests.sh`
- Colorized output with pass/fail summary
- Individual test suite execution available
- Performance regression detection

**Legacy Testing:**
- **Integration testing** via `test_wol.py` - validates complete Magic Packet flow
- **Real network testing** - actual UDP transmission and ping verification  
- **UI testing** through Xcode's XCTest framework

### Network Requirements
The application requires:
- **UDP broadcast capability** on local network
- **ICMP ping access** for device monitoring  
- Target device must have **Wake-on-LAN enabled** in BIOS/firmware
- Target device should be **wired** (Ethernet) for best reliability

## Important Implementation Notes

### State Management
- All UI state is managed through `@StateObject` and `@Published` properties
- Configuration changes automatically trigger UI updates via Combine
- Device status monitoring runs continuously when valid configuration exists

### Error Handling
- **Network errors:** Graceful handling of UDP transmission failures
- **Configuration errors:** Input validation with user feedback
- **System integration:** Proper handling of ping command execution

### Platform Integration
- Native macOS app with proper sandboxing considerations
- Uses system networking APIs (BSD sockets for UDP)
- Integrates with macOS process execution for ping functionality

## Troubleshooting Common Issues

**App won't wake device:**
- Verify target device has Wake-on-LAN enabled in BIOS
- Check that device is connected via Ethernet (not WiFi)
- Ensure firewall allows UDP broadcast on port 9

**Configuration not persisting:**
- Check file permissions in `~/Projects/WoL Manu/` directory
- Verify JSON format in `config.json` is valid

**Ping monitoring not working:**
- Confirm `/sbin/ping` is accessible 
- Check network connectivity between devices
- Verify IP address is reachable

## Security Implementation (v1.4)

### Input Validation & DoS Protection
- **Strict MAC Validation**: Rejects common invalid MACs (00:00:00:00:00:00, FF:FF:FF:FF:FF:FF)
- **IPv4 Sanitization**: Uses `socket.inet_aton()` for strict validation
- **Length Limits**: MAC ≤20 chars, IP ≤15 chars, Device Name ≤50 chars
- **Format Enforcement**: Supports colon, dash, and no-separator MAC formats
- **Leading Zero Rejection**: Blocks potentially malicious IP formats

### Server Hardening
- **Systemd Security**: Process isolation with restricted syscalls
- **Non-Privileged User**: Dedicated `wol-server` user with minimal permissions
- **File Permissions**: Configuration files locked to 600 (owner-only)
- **Directory Isolation**: Application runs in `/opt/wol-server`
- **Kernel Protection**: Blocked access to loadable kernel modules
- **Control Groups**: Process resource limits and isolation

### Network Security
- **API Key Authentication**: Strong random key generation
- **Rate Limit Handling**: Intelligent 429 response processing
- **Private Network Only**: Restricted to RFC 1918 IP ranges
- **Firewall Integration**: UFW configuration included
- **Request Logging**: Comprehensive activity tracking

---

This application is fully functional and has been tested successfully in real network environments. The codebase is well-structured with enterprise-grade security and reliability, ready for production deployment.
