import XCTest
@testable import WoL_Manu

class WakeOnLANServiceTests: XCTestCase {
    
    var service: WakeOnLANService!
    
    override func setUp() {
        super.setUp()
        service = WakeOnLANService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - MAC Address Parsing Tests
    
    func testParseMACAddress_ValidFormats() {
        // Test colon-separated MAC
        let mac1 = "00:1B:63:84:45:E6"
        let result1 = service.parseMACAddress(mac1)
        XCTAssertNotNil(result1, "Should parse colon-separated MAC address")
        XCTAssertEqual(result1?.count, 6, "MAC address should have 6 bytes")
        XCTAssertEqual(result1?[0], 0x00, "First byte should be 0x00")
        XCTAssertEqual(result1?[1], 0x1B, "Second byte should be 0x1B")
        XCTAssertEqual(result1?[5], 0xE6, "Last byte should be 0xE6")
        
        // Test hyphen-separated MAC
        let mac2 = "00-1B-63-84-45-E6"
        let result2 = service.parseMACAddress(mac2)
        XCTAssertNotNil(result2, "Should parse hyphen-separated MAC address")
        XCTAssertEqual(result2, result1, "Both formats should produce same result")
        
        // Test no-separator MAC
        let mac3 = "001B638445E6"
        let result3 = service.parseMACAddress(mac3)
        XCTAssertNotNil(result3, "Should parse MAC without separators")
        XCTAssertEqual(result3, result1, "No-separator format should produce same result")
        
        // Test lowercase
        let mac4 = "00:1b:63:84:45:e6"
        let result4 = service.parseMACAddress(mac4)
        XCTAssertNotNil(result4, "Should parse lowercase MAC address")
        XCTAssertEqual(result4, result1, "Lowercase should produce same result")
    }
    
    func testParseMACAddress_InvalidFormats() {
        // Test invalid length
        let invalidMAC1 = "00:1B:63:84:45"
        XCTAssertNil(service.parseMACAddress(invalidMAC1), "Should reject MAC with insufficient bytes")
        
        // Test invalid characters
        let invalidMAC2 = "00:1B:63:84:45:ZZ"
        XCTAssertNil(service.parseMACAddress(invalidMAC2), "Should reject MAC with invalid hex characters")
        
        // Test empty string
        XCTAssertNil(service.parseMACAddress(""), "Should reject empty MAC address")
        
        // Test too long
        let invalidMAC3 = "00:1B:63:84:45:E6:FF"
        XCTAssertNil(service.parseMACAddress(invalidMAC3), "Should reject MAC with too many bytes")
        
        // Test mixed separators
        let invalidMAC4 = "00:1B-63:84:45:E6"
        XCTAssertNil(service.parseMACAddress(invalidMAC4), "Should reject MAC with mixed separators")
    }
    
    func testParseMACAddress_EdgeCases() {
        // Test broadcast MAC
        let broadcastMAC = "FF:FF:FF:FF:FF:FF"
        let result = service.parseMACAddress(broadcastMAC)
        XCTAssertNotNil(result, "Should parse broadcast MAC")
        XCTAssertEqual(result?.allSatisfy { $0 == 0xFF }, true, "All bytes should be 0xFF")
        
        // Test all zeros MAC
        let zeroMAC = "00:00:00:00:00:00"
        let result2 = service.parseMACAddress(zeroMAC)
        XCTAssertNotNil(result2, "Should parse all-zeros MAC")
        XCTAssertEqual(result2?.allSatisfy { $0 == 0x00 }, true, "All bytes should be 0x00")
    }
    
    // MARK: - Magic Packet Construction Tests
    
    func testBuildMagicPacket_ValidMAC() {
        let macBytes: [UInt8] = [0x00, 0x1B, 0x63, 0x84, 0x45, 0xE6]
        guard let magicPacket = service.buildMagicPacket(macBytes: macBytes) else {
            XCTFail("Should build magic packet for valid MAC")
            return
        }
        
        // Magic packet should be exactly 102 bytes
        XCTAssertEqual(magicPacket.count, 102, "Magic packet should be 102 bytes")
        
        // First 6 bytes should be 0xFF
        let preamble = Array(magicPacket[0..<6])
        XCTAssertEqual(preamble, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], "Preamble should be 6 bytes of 0xFF")
        
        // Next 96 bytes should be 16 repetitions of the MAC address
        for i in 0..<16 {
            let start = 6 + (i * 6)
            let end = start + 6
            let macRepetition = Array(magicPacket[start..<end])
            XCTAssertEqual(macRepetition, macBytes, "Repetition \(i) should match original MAC")
        }
    }
    
    func testBuildMagicPacket_InvalidMAC() {
        // Test with wrong MAC length
        let invalidMACBytes: [UInt8] = [0x00, 0x1B, 0x63, 0x84, 0x45] // Only 5 bytes
        XCTAssertNil(service.buildMagicPacket(macBytes: invalidMACBytes), "Should reject MAC with wrong length")
        
        // Test with empty MAC
        let emptyMACBytes: [UInt8] = []
        XCTAssertNil(service.buildMagicPacket(macBytes: emptyMACBytes), "Should reject empty MAC bytes")
    }
    
    // MARK: - Integration Tests
    
    func testMACParsingAndMagicPacketIntegration() {
        let macString = "00:1B:63:84:45:E6"
        
        guard let macBytes = service.parseMACAddress(macString) else {
            XCTFail("Should parse valid MAC string")
            return
        }
        
        guard let magicPacket = service.buildMagicPacket(macBytes: macBytes) else {
            XCTFail("Should build magic packet from parsed MAC")
            return
        }
        
        // Verify the complete flow works correctly
        XCTAssertEqual(magicPacket.count, 102, "Magic packet should have correct size")
        
        // Verify preamble
        let preamble = Array(magicPacket[0..<6])
        XCTAssertEqual(preamble, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], "Should have correct preamble")
        
        // Verify MAC repetitions
        for i in 0..<16 {
            let start = 6 + (i * 6)
            let end = start + 6
            let repetition = Array(magicPacket[start..<end])
            XCTAssertEqual(repetition, [0x00, 0x1B, 0x63, 0x84, 0x45, 0xE6], "MAC repetition \(i) should be correct")
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_MACParsing() {
        let testMACs = [
            "00:1B:63:84:45:E6",
            "AA:BB:CC:DD:EE:FF",
            "11-22-33-44-55-66",
            "AABBCCDDEEFF",
            "ff:ff:ff:ff:ff:ff"
        ]
        
        measure {
            for _ in 0..<1000 {
                for mac in testMACs {
                    _ = service.parseMACAddress(mac)
                }
            }
        }
    }
    
    func testPerformance_MagicPacketConstruction() {
        let macBytes: [UInt8] = [0x00, 0x1B, 0x63, 0x84, 0x45, 0xE6]
        
        measure {
            for _ in 0..<1000 {
                _ = service.buildMagicPacket(macBytes: macBytes)
            }
        }
    }
}