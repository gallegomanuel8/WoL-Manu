import XCTest
@testable import WoL_Manu

class NetworkScannerTests: XCTestCase {

    // MARK: - IP Range Parsing

    func testParseRange_FullAddresses() {
        let r = IPv4.parseRange(from: "192.168.1.95", to: "192.168.1.120")
        XCTAssertEqual(r.map { IPv4.string($0.first) }, "192.168.1.95")
        XCTAssertEqual(r.map { IPv4.string($0.last) }, "192.168.1.120")
    }

    func testParseRange_LastOctetShorthand() {
        let r = IPv4.parseRange(from: "192.168.1.95", to: "120")
        XCTAssertEqual(r.map { IPv4.string($0.last) }, "192.168.1.120", "'Hasta' with only the last octet should reuse the first three")
    }

    func testParseRange_AcrossSubnets() {
        let r = IPv4.parseRange(from: "10.0.0.250", to: "10.0.1.5")
        XCTAssertEqual(r.map { Int($0.last - $0.first) + 1 }, 12)
    }

    func testParseRange_Invalid() {
        XCTAssertNil(IPv4.parseRange(from: "192.168.3", to: "10"), "Incomplete 'Desde' should be rejected")
        XCTAssertNil(IPv4.parseRange(from: "192.168.1.1", to: "300"), "Octet above 255 should be rejected")
        XCTAssertNil(IPv4.parseRange(from: "192.168.1.1", to: "abc"))
        XCTAssertNil(IPv4.parseRange(from: "", to: ""))
    }

    // MARK: - ScanTarget

    func testScanTarget_HostsAndContains() {
        let first = IPv4.parse("192.168.1.95")!
        let last = IPv4.parse("192.168.1.120")!
        let target = ScanTarget(first: first, last: last, label: "", interfaceName: nil, localAddress: nil, localMAC: nil)

        XCTAssertEqual(target.count, 26)
        XCTAssertEqual(target.hosts.count, 26)
        XCTAssertEqual(target.hosts.first, first)
        XCTAssertEqual(target.hosts.last, last)
        XCTAssertTrue(target.contains(IPv4.parse("192.168.1.99")!))
        XCTAssertFalse(target.contains(IPv4.parse("192.168.1.94")!))
        XCTAssertFalse(target.contains(IPv4.parse("192.168.1.121")!))
    }

    func testScanTarget_ReversedRangeIsEmpty() {
        let target = ScanTarget(first: IPv4.parse("192.168.1.50")!, last: IPv4.parse("192.168.1.10")!,
                                label: "", interfaceName: nil, localAddress: nil, localMAC: nil)
        XCTAssertEqual(target.count, 0)
        XCTAssertTrue(target.hosts.isEmpty)
    }

    func testInterfaceTarget_ExcludesNetworkAndBroadcast() {
        let iface = NetworkInterfaceInfo(name: "en0", address: IPv4.parse("192.168.1.105")!,
                                         netmask: IPv4.parse("255.255.255.0")!, mac: nil)
        XCTAssertEqual(iface.target.label, "192.168.1.0/24")
        XCTAssertEqual(iface.target.first, IPv4.parse("192.168.1.1"))
        XCTAssertEqual(iface.target.last, IPv4.parse("192.168.1.254"))
        XCTAssertTrue(iface.contains(IPv4.parse("192.168.1.200")!))
        XCTAssertFalse(iface.contains(IPv4.parse("192.168.4.1")!))
    }
    
    // MARK: - Vendor (OUI) & device type
    
    func testVendorLookup() {
        let db = OUIDatabase.shared
        XCTAssertEqual(db.vendor(for: "70:85:C2:00:00:01"), "ASRock")
        XCTAssertEqual(db.vendor(for: "bc-24-11-00-00-01"), "Proxmox Server Solutions", "Should accept lowercase and dashes")
        XCTAssertEqual(db.vendor(for: "B8:27:EB:00:00:01"), "Raspberry Pi Foundation")
        XCTAssertNil(db.vendor(for: "not a mac"))
    }
    
    func testVendorLookup_PrefersMostSpecificBlock() {
        // 70:B3:D5 es un bloque MA-S (/36): cada sub-bloque tiene su propio fabricante
        let db = OUIDatabase.shared
        XCTAssertEqual(db.vendor(for: "70:B3:D5:00:1A:BC"), "SOREDI touch systems", "Should resolve the /36 owner")
        XCTAssertEqual(db.vendor(for: "70:B3:D5:00:2A:BC"), "Gogo BA")
    }
    
    func testClassifier() {
        func host(_ mac: String?, ports: [UInt16] = [], name: String? = nil) -> ScannedHost {
            var h = ScannedHost(ip: 1, mac: mac, hostname: name)
            h.openPorts = ports.map { OpenPort(port: $0, name: "") }
            return h
        }
        XCTAssertEqual(host("BC:24:11:00:00:01", ports: [22]).kind, .virtualMachine)
        XCTAssertEqual(host("FC:12:63:00:00:01").kind, .router, "Askey → router")
        XCTAssertEqual(host("70:85:C2:00:00:02").kind, .computer, "ASRock → PC")
        XCTAssertEqual(host("AA:00:00:00:00:01").kind, .mobilePrivate)
        XCTAssertEqual(host("AA:00:00:00:00:01", name: "iPhone-de-prueba.local").kind, .phone)
        XCTAssertEqual(host("84:B8:B8:00:00:01").kind, .phone, "Motorola → móvil")
        XCTAssertEqual(host(nil, ports: [9100]).kind, .printer)
        XCTAssertEqual(host(nil).kind, .unknown)
    }
}
