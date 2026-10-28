//
//  NetworkScanner.swift
//  WoL Manu
//
//  Descubre equipos en una subred: ping, tabla ARP (MAC), DNS/NetBIOS (nombre)
//  y comprobación rápida de puertos TCP habituales.
//

import Foundation
import Darwin
import Combine

// MARK: - IPv4 helpers

nonisolated enum IPv4 {
    static func string(_ ip: UInt32) -> String {
        "\(ip >> 24 & 0xFF).\(ip >> 16 & 0xFF).\(ip >> 8 & 0xFF).\(ip & 0xFF)"
    }

    static func parse(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var ip: UInt32 = 0
        for p in parts {
            guard let v = UInt32(p), v <= 255 else { return nil }
            ip = ip << 8 | v
        }
        return ip
    }

    static func mask(prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : UInt32.max << UInt32(32 - min(prefix, 32))
    }

    /// "192.168.3.0/24" o "192.168.3.7" (se asume /24)
    static func parseCIDR(_ s: String) -> (network: UInt32, prefix: Int)? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard let first = parts.first, let ip = parse(String(first)) else { return nil }
        let prefix = parts.count > 1 ? Int(parts[1]) ?? -1 : 24
        guard (16...30).contains(prefix) else { return nil }
        return (ip & mask(prefix: prefix), prefix)
    }
}

// MARK: - Models

nonisolated struct ScanTarget: Hashable, Sendable {
    let network: UInt32
    let prefix: Int
    let interfaceName: String?
    let localAddress: UInt32?
    let localMAC: String?

    var cidr: String { "\(IPv4.string(network))/\(prefix)" }
    var mask: UInt32 { IPv4.mask(prefix: prefix) }

    var hosts: [UInt32] {
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return Array((network + 1)..<broadcast)
    }

    func contains(_ ip: UInt32) -> Bool { ip & mask == network }
}

nonisolated struct NetworkInterfaceInfo: Identifiable, Hashable, Sendable {
    let name: String
    let address: UInt32
    let netmask: UInt32
    let mac: String?

    var id: String { name }
    var prefix: Int { netmask.nonzeroBitCount }
    var addressString: String { IPv4.string(address) }
    var isTunnel: Bool { name.hasPrefix("utun") || name.hasPrefix("wg") }

    /// Redes mayores de /22 se limitan a la /24 propia para que el escaneo sea razonable
    var target: ScanTarget {
        let p = max(prefix, prefix < 22 ? 24 : prefix)
        return ScanTarget(network: address & IPv4.mask(prefix: p), prefix: p,
                          interfaceName: name, localAddress: address, localMAC: mac)
    }
}

nonisolated struct OpenPort: Hashable, Sendable {
    let port: UInt16
    let name: String
}

nonisolated enum HostKind: Sendable {
    case thisMac, router, computer, phone, printer, server, unknown

    var symbol: String {
        switch self {
        case .thisMac: "laptopcomputer"
        case .router: "wifi.router"
        case .computer: "desktopcomputer"
        case .phone: "iphone"
        case .printer: "printer"
        case .server: "server.rack"
        case .unknown: "network"
        }
    }

    var label: String {
        switch self {
        case .thisMac: "Este Mac"
        case .router: "Router / puerta de enlace"
        case .computer: "Ordenador"
        case .phone: "iPhone / iPad"
        case .printer: "Impresora"
        case .server: "Servidor"
        case .unknown: "Dispositivo"
        }
    }
}

nonisolated struct ScannedHost: Identifiable, Hashable, Sendable {
    let ip: UInt32
    var mac: String?
    var hostname: String?
    var latencyMs: Double?
    var openPorts: [OpenPort] = []
    var isThisMac = false
    var isGateway = false

    var id: UInt32 { ip }
    var ipString: String { IPv4.string(ip) }

    /// Bit "localmente administrado": MAC aleatoria (privada) de iOS/macOS/Android
    var isPrivateMAC: Bool {
        guard let first = mac?.prefix(2), let byte = UInt8(first, radix: 16) else { return false }
        return byte & 0x02 != 0
    }

    var kind: HostKind {
        let ports = Set(openPorts.map(\.port))
        if isThisMac { return .thisMac }
        if isGateway { return .router }
        if ports.contains(62078) { return .phone }
        if !ports.isDisjoint(with: [9100, 631, 515]) { return .printer }
        if !ports.isDisjoint(with: [3389, 445, 139, 548, 5900]) { return .computer }
        if !ports.isDisjoint(with: [22, 80, 443, 5000, 8080, 53]) { return .server }
        return .unknown
    }

    // Claves de ordenación para la tabla
    var nameSort: String { hostname?.lowercased() ?? "\u{10FFFF}" }
    var macSort: String { mac ?? "\u{10FFFF}" }
    var latencySort: Double { latencyMs ?? .infinity }
}

// MARK: - Scanner

@MainActor
final class NetworkScanner: ObservableObject {
    enum Phase: Equatable {
        case idle, discovering, resolving, probingPorts, done, cancelled

        var label: String {
            switch self {
            case .idle: "Listo para escanear"
            case .discovering: "Buscando equipos…"
            case .resolving: "Resolviendo nombres…"
            case .probingPorts: "Comprobando servicios…"
            case .done: "Escaneo completado"
            case .cancelled: "Escaneo detenido"
            }
        }
    }

    @Published private(set) var interfaces: [NetworkInterfaceInfo] = []
    @Published private(set) var hosts: [ScannedHost] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastTarget: ScanTarget?
    @Published private(set) var lastScanDate: Date?

    private var scanTask: Task<Void, Never>?
    private var found: [UInt32: ScannedHost] = [:]

    var isScanning: Bool { [.discovering, .resolving, .probingPorts].contains(phase) }

    init() {
        refreshInterfaces()
    }

    func refreshInterfaces() {
        interfaces = NetworkProbe.interfaces()
    }

    func scan(_ target: ScanTarget) {
        scanTask?.cancel()
        scanTask = Task { await run(target) }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = .cancelled
    }

    /// Vuelve a comprobar los puertos de un único equipo
    func rescanPorts(of id: UInt32) {
        Task {
            let ports = await NetworkProbe.openPorts(id)
            found[id]?.openPorts = ports
            publish()
        }
    }

    // MARK: Pipeline

    private func run(_ target: ScanTarget) async {
        found = [:]
        hosts = []
        lastTarget = target
        progress = 0
        phase = .discovering

        let gateway = await NetworkProbe.defaultGateway()
        if let local = target.localAddress {
            found[local] = ScannedHost(ip: local, mac: target.localMAC, hostname: Host.current().localizedName, latencyMs: 0, isThisMac: true)
            publish()
        }

        // 1. Ping sweep (ventana deslizante de 64 pings simultáneos)
        let targets = target.hosts.filter { $0 != target.localAddress }
        var completed = 0
        await withTaskGroup(of: (UInt32, Double?).self) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<64 {
                guard let ip = iterator.next() else { break }
                group.addTask { (ip, await NetworkProbe.ping(ip)) }
            }
            for await (ip, latency) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                completed += 1
                progress = Double(completed) / Double(max(targets.count, 1))
                if let latency {
                    found[ip, default: ScannedHost(ip: ip)].latencyMs = latency
                    publish()
                }
                if let ip = iterator.next() {
                    group.addTask { (ip, await NetworkProbe.ping(ip)) }
                }
            }
        }
        guard !Task.isCancelled else { return }

        // 2. Tabla ARP: MAC de los que respondieron y de los que bloquean ICMP (p. ej. Windows)
        if let iface = target.interfaceName {
            for (ip, mac) in await NetworkProbe.arpTable(interface: iface) where target.contains(ip) {
                found[ip, default: ScannedHost(ip: ip)].mac = mac
            }
        }
        if let gateway, found[gateway] != nil {
            found[gateway]?.isGateway = true
        }
        publish()

        // 3. Nombres (DNS inverso, con NetBIOS como respaldo)
        phase = .resolving
        progress = 0
        let ips = Array(found.keys)
        let onLocalNetwork = target.interfaceName != nil
        await forEachConcurrently(ips, limit: 16) { ip in
            (ip, await NetworkProbe.hostname(ip, onLocalNetwork: onLocalNetwork))
        } handle: { (result: (UInt32, String?)) in
            if let name = result.1 { self.found[result.0]?.hostname = name }
        }
        guard !Task.isCancelled else { return }

        // 4. Servicios
        phase = .probingPorts
        progress = 0
        await forEachConcurrently(ips, limit: 8) { ip in
            (ip, await NetworkProbe.openPorts(ip))
        } handle: { (result: (UInt32, [OpenPort])) in
            self.found[result.0]?.openPorts = result.1
        }
        guard !Task.isCancelled else { return }

        progress = 1
        phase = .done
        lastScanDate = Date()
        scanTask = nil
    }

    private func forEachConcurrently<R: Sendable>(
        _ items: [UInt32],
        limit: Int,
        work: @escaping @Sendable (UInt32) async -> R,
        handle: (R) -> Void
    ) async {
        var completed = 0
        await withTaskGroup(of: R.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<limit {
                guard let item = iterator.next() else { break }
                group.addTask { await work(item) }
            }
            for await result in group {
                if Task.isCancelled { group.cancelAll(); continue }
                handle(result)
                completed += 1
                progress = Double(completed) / Double(max(items.count, 1))
                publish()
                if let item = iterator.next() {
                    group.addTask { await work(item) }
                }
            }
        }
    }

    private func publish() {
        hosts = found.values.sorted { $0.ip < $1.ip }
    }
}

// MARK: - Probes (fuera del hilo principal)

nonisolated enum NetworkProbe {
    static let commonPorts: [(UInt16, String)] = [
        (22, "SSH"), (53, "DNS"), (80, "HTTP"), (139, "NetBIOS"), (443, "HTTPS"),
        (445, "SMB"), (548, "AFP"), (631, "IPP"), (3389, "RDP"), (5000, "HTTP 5000"),
        (5900, "VNC"), (8080, "HTTP 8080"), (9100, "Impresión"), (62078, "Sync iOS")
    ]

    // MARK: Interfaces

    static func interfaces() -> [NetworkInterfaceInfo] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var macs: [String: String] = [:]
        var v4: [(String, UInt32, UInt32)] = []

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)

            switch Int32(sa.pointee.sa_family) {
            case AF_LINK:
                sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl in
                    guard sdl.pointee.sdl_alen == 6 else { return }
                    let offset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(sdl.pointee.sdl_nlen)
                    let base = UnsafeRawPointer(sdl).advanced(by: offset)
                    macs[name] = (0..<6).map { String(format: "%02X", base.load(fromByteOffset: $0, as: UInt8.self)) }
                        .joined(separator: ":")
                }
            case AF_INET:
                guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                      let mask = ifa.ifa_netmask else { continue }
                let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let nm = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                guard ip >> 16 != 0xA9FE else { continue } // 169.254.x.x
                v4.append((name, ip, nm))
            default:
                break
            }
        }

        return v4
            .map { NetworkInterfaceInfo(name: $0.0, address: $0.1, netmask: $0.2, mac: macs[$0.0]) }
            .sorted { ($0.isTunnel ? 1 : 0, $0.name) < ($1.isTunnel ? 1 : 0, $1.name) }
    }

    // MARK: Ping / ARP / gateway

    /// Latencia en ms, o nil si no responde
    static func ping(_ ip: UInt32) async -> Double? {
        let (status, output) = await run("/sbin/ping", ["-c", "1", "-W", "800", "-n", IPv4.string(ip)], timeout: 2)
        guard status == 0,
              let range = output.range(of: #"time=([0-9.]+)"#, options: .regularExpression) else { return nil }
        return Double(output[range].dropFirst(5))
    }

    static func arpTable(interface: String) async -> [UInt32: String] {
        let (_, output) = await run("/usr/sbin/arp", ["-an", "-i", interface], timeout: 5)
        var table: [UInt32: String] = [:]
        let regex = #/\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-fA-F:]+) on/#
        for line in output.split(separator: "\n") {
            guard let m = line.firstMatch(of: regex), let ip = IPv4.parse(String(m.1)) else { continue }
            let octets = m.2.split(separator: ":").map { $0.count == 1 ? "0\($0)" : String($0) }
            guard octets.count == 6 else { continue }
            let mac = octets.joined(separator: ":").uppercased()
            // Broadcast y multicast no son equipos
            if mac == "FF:FF:FF:FF:FF:FF" || mac.hasPrefix("01:00:5E") { continue }
            table[ip] = mac
        }
        return table
    }

    static func defaultGateway() async -> UInt32? {
        let (_, output) = await run("/sbin/route", ["-n", "get", "default"], timeout: 3)
        guard let m = output.firstMatch(of: #/gateway: (\d+\.\d+\.\d+\.\d+)/#) else { return nil }
        return IPv4.parse(String(m.1))
    }

    // MARK: Nombres

    /// DNS inverso → mDNS/Bonjour (solo en la red local: el multicast no cruza la VPN) → NetBIOS
    static func hostname(_ ip: UInt32, onLocalNetwork: Bool) async -> String? {
        if let name = await reverseDNS(ip) { return name }
        if onLocalNetwork, let name = await mdnsName(ip) { return name }
        return await netbiosName(ip)
    }
    
    private static func mdnsName(_ ip: UInt32) async -> String? {
        let (_, output) = await run("/usr/bin/dig", ["+short", "+time=1", "+tries=1", "-p", "5353", "@224.0.0.251", "-x", IPv4.string(ip)], timeout: 2)
        let name = output.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard let name, !name.isEmpty, !name.hasPrefix(";") else { return nil }
        return name
    }

    private static func reverseDNS(_ ip: UInt32) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_addr.s_addr = ip.bigEndian
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }
                guard rc == 0 else { return continuation.resume(returning: nil) }
                let name = String(cString: host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                continuation.resume(returning: name.isEmpty ? nil : name)
            }
        }
    }

    private static func netbiosName(_ ip: UInt32) async -> String? {
        let (status, output) = await run("/usr/bin/smbutil", ["status", "-ae", IPv4.string(ip)], timeout: 2)
        guard status == 0, let m = output.firstMatch(of: #/Server:\s*(\S+)/#) else { return nil }
        return String(m.1)
    }

    // MARK: Puertos

    static func openPorts(_ ip: UInt32) async -> [OpenPort] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var open = [Bool](repeating: false, count: commonPorts.count)
                open.withUnsafeMutableBufferPointer { buffer in
                    DispatchQueue.concurrentPerform(iterations: commonPorts.count) { i in
                        buffer[i] = isPortOpen(ip, commonPorts[i].0, timeoutMs: 600)
                    }
                }
                let result = commonPorts.indices.filter { open[$0] }.map { OpenPort(port: commonPorts[$0].0, name: commonPorts[$0].1) }
                continuation.resume(returning: result)
            }
        }
    }

    private static func isPortOpen(_ ip: UInt32, _ port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = ip.bigEndian

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, timeoutMs) == 1 else { return false }

        var error: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len)
        return error == 0
    }

    // MARK: Process

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (proc.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: (-1, ""))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
