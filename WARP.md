# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a **Wake-on-LAN application for macOS** - a native SwiftUI app that sends Magic Packets to remotely wake up network devices. The application is fully functional and production-ready.

**Key Facts:**
- **Language:** Swift 5.7+
- **UI Framework:** SwiftUI 
- **Platform:** macOS 12.0+
- **Architecture:** MVVM pattern with reactive programming (Combine)
- **Project Status:** ✅ Complete and fully functional

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

### Testing
```bash
# Run the Wake-on-LAN functionality test (Python script)
python3 test_wol.py

# Run Xcode tests (if available)
xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" test
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
┌─────────────────────────────────────┐
│            Views (SwiftUI)          │
│  • ContentView (Main Interface)     │
│  • ConfigurationView (Settings)     │
└─────────────────────────────────────┘
                   │
┌─────────────────────────────────────┐
│         ViewModels/Services         │
│  • ConfigurationManager (@Published)│
│  • PingService (Device Monitoring)  │
│  • WakeOnLANService (UDP Broadcast) │
└─────────────────────────────────────┘
                   │
┌─────────────────────────────────────┐
│              Models                 │
│  • DeviceConfiguration (Codable)    │
│  • Network packet handling          │
└─────────────────────────────────────┘
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

### Network Implementation Details

**Magic Packet Construction:**
- Format: 6 bytes of `0xFF` + 16 repetitions of the target MAC address
- Total size: 102 bytes
- Sent via UDP broadcast to port 9 (standard Wake-on-LAN port)

**Device Monitoring:**
- Uses system `ping` command: `ping -c 1 -W 3000 <IP>`
- 5-second intervals with visual status indicators (green/red circles)
- Reactive UI updates via Combine publishers

### File Structure
```
WoL Manu/
├── WoL_ManuApp.swift          # @main entry point
├── ContentView.swift          # Primary interface (350×500px)
├── ConfigurationView.swift    # Settings modal (400×350px)  
├── ConfigurationModel.swift   # DeviceConfiguration model + persistence
├── WakeOnLANService.swift     # UDP Magic Packet transmission
└── PingService.swift          # Device monitoring service

Root Directory:
├── config.json               # Runtime device configuration
├── run_app.sh               # Launch script  
├── test_wol.py             # Python test suite
├── test_report.md          # Comprehensive test results
└── RESUMEN_PROYECTO.md     # Detailed project summary (Spanish)
```

## Development Context

### Configuration Storage
- **Location:** `~/Projects/WoL Manu/config.json`
- **Format:** JSON with `deviceName`, `ipAddress`, `macAddress`
- **Validation:** IP format validation + MAC address parsing (supports `:`, `-`, or no separators)

### Testing Strategy
- **Integration testing** via `test_wol.py` - validates complete Magic Packet flow
- **Real network testing** - actual UDP transmission and ping verification
- **UI testing** through Xcode's XCTest framework (test targets available)

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

This application is fully functional and has been tested successfully in real network environments. The codebase is well-structured and ready for production use or further development.