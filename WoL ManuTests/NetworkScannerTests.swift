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
}
