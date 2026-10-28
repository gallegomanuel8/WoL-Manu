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
import Network

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

    /// Rango "desde–hasta". `to` puede ser una IP completa o solo el último octeto ("50").
    static func parseRange(from: String, to: String) -> (first: UInt32, last: UInt32)? {
        guard let first = parse(from.trimmingCharacters(in: .whitespaces)) else { return nil }
        let toText = to.trimmingCharacters(in: .whitespaces)
        let last: UInt32
        if let full = parse(toText) {
            last = full
        } else if let octet = UInt32(toText), octet <= 255 {
            last = first & 0xFFFF_FF00 | octet
        } else {
            return nil
        }
        return (first, last)
    }
}

// MARK: - Models

nonisolated struct ScanTarget: Hashable, Sendable {
    static let maxHosts = 4096
    
    let first: UInt32
    let last: UInt32
    let label: String
    let interfaceName: String?
    let localAddress: UInt32?
    let localMAC: String?
    
    var count: Int { first <= last ? Int(last - first) + 1 : 0 }
    var hosts: [UInt32] { first <= last ? Array(first...last) : [] }
    
    func contains(_ ip: UInt32) -> Bool { first <= ip && ip <= last }
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
        let mask = IPv4.mask(prefix: p)
        let network = address & mask
        return ScanTarget(first: network + 1, last: (network | ~mask) - 1,
                          label: "\(IPv4.string(network))/\(p)",
                          interfaceName: name, localAddress: address, localMAC: mac)
    }
    
    func contains(_ ip: UInt32) -> Bool { ip & netmask == address & netmask }
}

nonisolated struct OpenPort: Hashable, Sendable {
    let port: UInt16
    let name: String
}

nonisolated enum HostKind: Sendable {
    case thisMac, router, computer, phone, mobilePrivate, printer, server, nas, virtualMachine
    case media, speaker, camera, iot, console, unknown
    
    var symbol: String {
        switch self {
        case .thisMac: "laptopcomputer"
        case .router: "wifi.router"
        case .computer: "desktopcomputer"
        case .phone: "iphone"
        case .mobilePrivate: "iphone.gen3"
        case .printer: "printer"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .virtualMachine: "square.stack.3d.up"
        case .media: "tv"
        case .speaker: "hifispeaker"
        case .camera: "video"
        case .iot: "lightbulb.led"
        case .console: "gamecontroller"
        case .unknown: "network"
        }
    }
    
    var label: String {
        switch self {
        case .thisMac: "Este Mac"
        case .router: "Router / red"
        case .computer: "Ordenador"
        case .phone: "Móvil / tablet"
        case .mobilePrivate: "Móvil (MAC privada)"
        case .printer: "Impresora"
        case .server: "Servidor"
        case .nas: "NAS"
        case .virtualMachine: "Máquina virtual"
        case .media: "TV / multimedia"
        case .speaker: "Altavoz"
        case .camera: "Cámara"
        case .iot: "IoT / domótica"
        case .console: "Consola"
        case .unknown: "Desconocido"
        }
    }
}

nonisolated struct ScannedHost: Identifiable, Hashable, Sendable {
    let ip: UInt32
    var mac: String? {
        didSet { vendor = mac.flatMap(OUIDatabase.shared.vendor(for:)) }
    }
    private(set) var vendor: String?
    var hostname: String?
    var latencyMs: Double?
    var openPorts: [OpenPort] = []
    var isThisMac = false
    var isGateway = false
    /// MAC no vista en ningún escaneo anterior
    var isNew = false
    
    init(ip: UInt32, mac: String? = nil, hostname: String? = nil, latencyMs: Double? = nil, isThisMac: Bool = false) {
        self.ip = ip
        self.hostname = hostname
        self.latencyMs = latencyMs
        self.isThisMac = isThisMac
        self.mac = mac
        self.vendor = mac.flatMap(OUIDatabase.shared.vendor(for:))
    }
    
    var id: UInt32 { ip }
    var ipString: String { IPv4.string(ip) }
    
    /// Bit "localmente administrado": MAC aleatoria (privada) de iOS/macOS/Android
    var isPrivateMAC: Bool {
        guard let first = mac?.prefix(2), let byte = UInt8(first, radix: 16) else { return false }
        return byte & 0x02 != 0
    }
    
    var kind: HostKind { DeviceClassifier.classify(self) }
    
    /// "Router / red · Askey Computer", "Máquina virtual · Proxmox Server Solutions"…
    var deviceDescription: String {
        guard let vendor else { return kind.label }
        return "\(kind.label) · \(vendor)"
    }
    
    // Claves de ordenación para la tabla
    var nameSort: String { hostname?.lowercased() ?? "\u{10FFFF}" }
    var macSort: String { mac ?? "\u{10FFFF}" }
    var latencySort: Double { latencyMs ?? .infinity }
    var deviceSort: String { kind == .unknown ? "\u{10FFFF}" : deviceDescription.lowercased() }
}

// MARK: - Fabricante (OUI)

/// Prefijos MAC → fabricante, desde `oui.txt` (ver scripts/update_oui.py). Se carga una vez, bajo demanda.
nonisolated final class OUIDatabase: Sendable {
    static let shared = OUIDatabase()
    
    private let entries: [String: String]
    
    private init() {
        var entries: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "oui", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            entries.reserveCapacity(60_000)
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                guard let tab = line.firstIndex(of: "\t") else { continue }
                entries[String(line[..<tab])] = String(line[line.index(after: tab)...])
            }
        }
        self.entries = entries
    }
    
    func vendor(for mac: String) -> String? {
        let hex = mac.filter(\.isHexDigit).uppercased()
        guard hex.count == 12 else { return nil }
        // Bloques más específicos primero: MA-S (/36), MA-M (/28), MA-L (/24)
        for bits in [36, 28, 24] {
            if let name = entries["\(hex.prefix(bits / 4))/\(bits)"] { return name }
        }
        return nil
    }
}

// MARK: - Tipo de dispositivo

nonisolated enum DeviceClassifier {
    /// Prefijos de NICs virtuales (hipervisores)
    private static let virtualPrefixes = [
        "52:54:00", // QEMU / KVM
        "BC:24:11", // Proxmox
        "08:00:27", // VirtualBox
        "00:15:5D", // Hyper-V
        "00:1C:42", // Parallels
        "00:50:56", "00:0C:29", "00:05:69", // VMware
        "00:16:3E", // Xen
    ]
    
    private static let vendorKinds: [(HostKind, [String])] = [
        (.virtualMachine, ["proxmox", "vmware", "parallels", "xensource"]),
        (.nas, ["synology", "qnap", "asustor", "buffalo", "western digital", "terramaster"]),
        (.camera, ["hikvision", "dahua", "reolink", "axis communications", "ezviz", "foscam", "amcrest", "arlo"]),
        (.printer, ["brother", "seiko epson", "canon", "xerox", "kyocera", "lexmark", "ricoh", "konica"]),
        (.speaker, ["sonos", "bose", "harman", "bang & olufsen", "denon", "yamaha"]),
        (.console, ["nintendo", "sony interactive", "valve"]),
        (.phone, ["motorola", "oneplus", "oppo", "vivo mobile", "realme", "honor device", "nothing technology",
                  "fairphone", "zte mobile", "huawei device"]),
        (.media, ["roku", "tp vision", "hisense", "tcl", "vizio", "lg electronics", "amazon", "google",
                  "apple tv", "nvidia", "sky uk", "skyworth"]),
        (.iot, ["espressif", "tuya", "shelly", "allterco", "signify", "philips lighting", "nest labs",
                "ring llc", "ecobee", "ikea", "itead", "broadlink", "xiaomi", "aqara", "lumi united",
                "texas instruments", "silicon laboratories", "nordic semiconductor", "netatmo", "tado"]),
        (.router, ["askey", "sercomm", "zte", "tp-link", "netgear", "ubiquiti", "mikrotik", "routerboard",
                   "avm", "arcadyan", "technicolor", "sagemcom", "mitrastar", "zyxel", "d-link", "linksys",
                   "cisco", "aruba", "juniper", "fortinet", "eero", "huawei", "comtrend", "observa", "teltonika"]),
        (.server, ["raspberry pi", "super micro", "supermicro"]),
        (.computer, ["asrock", "asustek", "gigabyte", "giga-byte", "micro-star", "elitegroup", "jetway",
                     "intel", "dell", "lenovo", "acer", "hewlett", "hp inc", "framework", "liteon",
                     "azurewave", "hon hai", "realtek", "shuttle", "zotac", "beelink", "minisforum"]),
    ]
    
    static func classify(_ host: ScannedHost) -> HostKind {
        let ports = Set(host.openPorts.map(\.port))
        let vendor = host.vendor?.lowercased() ?? ""
        let name = host.hostname?.lowercased() ?? ""
        
        if host.isThisMac { return .thisMac }
        if host.isGateway { return .router }
        if let mac = host.mac, virtualPrefixes.contains(where: mac.hasPrefix) { return .virtualMachine }
        
        // Pistas del nombre (mDNS/DNS)
        if ["iphone", "ipad", "android", "galaxy", "pixel", "redmi"].contains(where: name.contains) { return .phone }
        if ["macbook", "imac", "mac-mini", "macmini", "mac-studio", "desktop-", "laptop-", "-pc"].contains(where: name.contains) { return .computer }
        if ["appletv", "apple-tv", "chromecast", "roku", "firetv", "fire-tv"].contains(where: name.contains) { return .media }
        if name.contains("homepod") || name.contains("sonos") { return .speaker }
        
        // Servicios
        if ports.contains(62078) { return .phone }
        if !ports.isDisjoint(with: [9100, 631, 515]) { return .printer }
        
        // Fabricante
        // Coincidencia al inicio de palabra: evita que "zte" case con "Aztech" o "ring" con "Engineering"
        let paddedVendor = " " + vendor
        let byVendor = vendorKinds.first { _, keywords in
            keywords.contains { paddedVendor.contains(" " + $0) }
        }?.0
        if let byVendor, byVendor != .computer { return byVendor }
        
        if ports.contains(53) { return .server }
        if !ports.isDisjoint(with: [3389, 445, 139, 548, 5900]) { return .computer }
        if byVendor == .computer { return .computer }
        if !ports.isDisjoint(with: [22, 80, 443, 5000, 8080]) { return .server }
        if vendor.hasPrefix("apple") { return .phone }
        if host.isPrivateMAC { return .mobilePrivate }
        return .unknown
    }
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
    private let pathMonitor = NWPathMonitor()

    var isScanning: Bool { [.discovering, .resolving, .probingPorts].contains(phase) }

    init() {
        refreshInterfaces()
        // Cargar la base de fabricantes (≈60k entradas) fuera del hilo principal
        Task.detached(priority: .utility) { _ = OUIDatabase.shared }
        // Cambio de red (Wi-Fi, hotspot, VPN…): volver a leer las interfaces
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refreshInterfaces() }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }
    
    deinit {
        pathMonitor.cancel()
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

        // 2. Tabla ARP: MAC de los que respondieron y de los que bloquean ICMP (p. ej. Windows).
        //    Se filtra por rango, no por interfaz, para no depender de la detección de interfaces.
        for (ip, mac) in NetworkProbe.arpTable() where target.contains(ip) && ip != target.localAddress {
            found[ip, default: ScannedHost(ip: ip)].mac = mac
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

        // 5. Dispositivos nuevos (solo con MAC, es decir, en la red local)
        if target.interfaceName != nil {
            let newMACs = KnownDevicesStore.shared.register(Array(found.values))
            for (ip, host) in found where host.mac.map(newMACs.contains) == true {
                found[ip]?.isNew = true
            }
            publish()
            KnownDevicesStore.shared.notifyNewDevices(hosts.filter(\.isNew))
        }
        
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

    /// Tabla ARP leída en el propio proceso vía sysctl. Lanzar `arp` no sirve: macOS oculta
    /// la tabla a los procesos hijos de una app sin permiso de Red Local y devuelve vacío.
    static func arpTable() -> [UInt32: String] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return [:] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return [:] }
        
        // Los sockaddr van alineados a 4 bytes tras cada rt_msghdr
        func roundup(_ a: Int) -> Int { a > 0 ? 1 + ((a - 1) | 3) : 4 }
        
        var table: [UInt32: String] = [:]
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<rt_msghdr>.size <= len {
                let msglen = Int(raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self).rtm_msglen)
                guard msglen > 0 else { break }
                defer { offset += msglen }
                
                let sinOff = offset + MemoryLayout<rt_msghdr>.size
                let sin = raw.loadUnaligned(fromByteOffset: sinOff, as: sockaddr_in.self)
                let sdlOff = sinOff + roundup(Int(sin.sin_len))
                guard sdlOff + MemoryLayout<sockaddr_dl>.size <= offset + msglen else { continue }
                let sdl = raw.loadUnaligned(fromByteOffset: sdlOff, as: sockaddr_dl.self)
                guard sdl.sdl_alen == 6 else { continue }  // entradas incompletas
                
                let macOff = sdlOff + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(sdl.sdl_nlen)
                let mac = (0..<6).map { String(format: "%02X", raw[macOff + $0]) }.joined(separator: ":")
                // Broadcast y multicast no son equipos
                if mac == "FF:FF:FF:FF:FF:FF" || mac.hasPrefix("01:00:5E") { continue }
                table[UInt32(bigEndian: sin.sin_addr.s_addr)] = mac
            }
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

    static func reverseDNS(_ ip: UInt32) async -> String? {
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

    static func isPortOpen(_ ip: UInt32, _ port: UInt16, timeoutMs: Int32) -> Bool {
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

    static func run(_ path: String, _ args: [String], timeout: TimeInterval) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            // Leer mientras el proceso escribe: si la salida supera el buffer del pipe
            // (p. ej. `arp -an` tras un barrido), esperar al final lo bloquearía.
            let reader = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }
            process.terminationHandler = { proc in
                Task {
                    let data = await reader.value
                    continuation.resume(returning: (proc.terminationStatus, String(decoding: data, as: UTF8.self)))
                }
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
