//
//  NetworkTools.swift
//  WoL Manu
//
//  Motores de la ventana "Herramientas de red": ping continuo, traceroute,
//  escáner de puertos por rango y consultas DNS.
//

import Foundation
import Darwin
import Combine

// MARK: - Utilidades

nonisolated enum HostResolver {
    /// IPv4 de una IP o nombre de host (getaddrinfo, fuera del hilo principal)
    static func resolve(_ host: String) async -> UInt32? {
        let host = host.trimmingCharacters(in: .whitespaces)
        if let ip = IPv4.parse(host) { return ip }
        guard !host.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else {
                    return continuation.resume(returning: nil)
                }
                defer { freeaddrinfo(result) }
                let ip = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                continuation.resume(returning: ip)
            }
        }
    }
}

/// Lanza un proceso y entrega su salida (stdout + stderr) línea a línea
nonisolated final class LineStreamer: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private var buffer = Data()

    init(_ path: String, _ args: [String], onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: self.buffer[..<newline], as: UTF8.self)
                self.buffer.removeSubrange(...newline)
                onLine(line)
            }
        }
        process.terminationHandler = { onExit($0.terminationStatus) }
    }

    func start() throws { try process.run() }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}

// MARK: - Ping continuo

struct PingSample: Identifiable {
    let seq: Int
    let date: Date
    let ms: Double?
    var id: Int { seq }
}

final class PingMonitor: ObservableObject {
    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    @Published private(set) var resolvedAddress: String?

    private(set) var sent = 0
    private(set) var received = 0
    private var allTimes: [Double] = []
    private var streamer: LineStreamer?
    private let maxSamples = 300

    var lossPercent: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100 }
    var minMs: Double? { allTimes.min() }
    var maxMs: Double? { allTimes.max() }
    var avgMs: Double? { allTimes.isEmpty ? nil : allTimes.reduce(0, +) / Double(allTimes.count) }
    /// Media de la diferencia entre respuestas consecutivas
    var jitterMs: Double? {
        guard allTimes.count > 1 else { return nil }
        let diffs = zip(allTimes.dropFirst(), allTimes).map { abs($0 - $1) }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    func start(_ host: String, interval: Double = 1) {
        stop()
        samples = []
        allTimes = []
        sent = 0
        received = 0
        error = nil
        resolvedAddress = nil

        let streamer = LineStreamer("/sbin/ping", ["-n", "-i", String(interval), host]) { [weak self] line in
            Task { @MainActor in self?.handle(line) }
        } onExit: { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                if self.isRunning, status != 0, self.sent == 0 {
                    self.error = "No se pudo hacer ping a \(host)"
                }
                self.isRunning = false
            }
        }
        do {
            try streamer.start()
            self.streamer = streamer
            isRunning = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        isRunning = false
        streamer?.stop()
        streamer = nil
    }

    private func handle(_ line: String) {
        if resolvedAddress == nil, let m = line.firstMatch(of: #/^PING \S+ \(([\d.]+)\)/#) {
            resolvedAddress = String(m.1)
        } else if let m = line.firstMatch(of: #/icmp_seq=(\d+) .*time=([\d.]+) ms/#) {
            let ms = Double(m.2) ?? 0
            sent += 1
            received += 1
            allTimes.append(ms)
            append(PingSample(seq: Int(m.1) ?? sent, date: Date(), ms: ms))
        } else if let m = line.firstMatch(of: #/Request timeout for icmp_seq (\d+)/#) {
            sent += 1
            append(PingSample(seq: Int(m.1) ?? sent, date: Date(), ms: nil))
        } else if line.contains("cannot resolve") || line.contains("Unknown host") {
            error = "No se encuentra el equipo"
        }
    }

    private func append(_ sample: PingSample) {
        samples.append(sample)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
    }
}

// MARK: - Traceroute

struct TraceHop: Identifiable {
    let number: Int
    var address: String?
    var name: String?
    var ms: Double?
    var id: Int { number }
}

enum TraceProtocol: String, CaseIterable, Identifiable {
    /// Como `tracert` de Windows: pasa por cortafuegos que descartan UDP (p. ej. Windows)
    case icmp = "ICMP"
    /// Por defecto en macOS/Linux
    case udp = "UDP"
    var id: String { rawValue }
}

final class TracerouteRunner: ObservableObject {
    @Published private(set) var hops: [TraceHop] = []
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    @Published private(set) var destinationAddress: String?
    @Published private(set) var hasRun = false
    
    var reachedDestination: Bool {
        guard let destinationAddress else { return false }
        return hops.contains { $0.address == destinationAddress }
    }

    private var streamer: LineStreamer?

    func start(_ host: String, protocol proto: TraceProtocol = .icmp) {
        stop()
        hops = []
        error = nil
        destinationAddress = nil
        hasRun = true

        // -n: sin DNS (los nombres se resuelven aparte, sin frenar la traza); -q 1: una sonda por salto
        var args = ["-n", "-q", "1", "-w", "2", "-m", "30"]
        if proto == .icmp { args.append("-I") }
        let streamer = LineStreamer("/usr/sbin/traceroute", args + [host]) { [weak self] line in
            Task { @MainActor in self?.handle(line) }
        } onExit: { [weak self] _ in
            Task { @MainActor in self?.isRunning = false }
        }
        do {
            try streamer.start()
            self.streamer = streamer
            isRunning = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        streamer?.stop()
        streamer = nil
        isRunning = false
    }

    private func handle(_ line: String) {
        if let m = line.firstMatch(of: #/^traceroute to \S+ \(([\d.]+)\)/#) {
            destinationAddress = String(m.1)
        } else if let m = line.firstMatch(of: #/^\s*(\d+)\s+([\d.]+)\s+([\d.]+) ms/#) {
            let hop = TraceHop(number: Int(m.1) ?? 0, address: String(m.2), ms: Double(m.3))
            hops.append(hop)
            if let ip = IPv4.parse(String(m.2)) {
                Task {
                    let name = await NetworkProbe.reverseDNS(ip)
                    if let i = hops.firstIndex(where: { $0.number == hop.number }) { hops[i].name = name }
                }
            }
        } else if let m = line.firstMatch(of: #/^\s*(\d+)\s+\*/#) {
            hops.append(TraceHop(number: Int(m.1) ?? 0))
        } else if line.contains("unknown host") || line.contains("cannot resolve") {
            error = "No se encuentra el equipo"
        }
    }
}

// MARK: - Escáner de puertos

struct PortResult: Identifiable, Hashable {
    let port: UInt16
    let service: String?
    var id: UInt16 { port }
}

final class PortRangeScanner: ObservableObject {
    @Published private(set) var open: [PortResult] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""

    private var task: Task<Void, Never>?

    func start(host: String, range: ClosedRange<UInt16>, timeoutMs: Int32) {
        stop()
        open = []
        progress = 0
        status = "Resolviendo \(host)…"
        isRunning = true

        task = Task {
            guard let ip = await HostResolver.resolve(host) else {
                status = "No se encuentra el equipo"
                isRunning = false
                return
            }
            let started = Date()
            let ports = Array(range)
            let batchSize = PortRangeScanner.raiseFileLimit()
            var scanned = 0

            for chunk in stride(from: 0, to: ports.count, by: batchSize) {
                if Task.isCancelled { break }
                let batch = Array(ports[chunk..<min(chunk + batchSize, ports.count)])
                let found = await PortRangeScanner.scanBatch(ip, batch, timeoutMs: timeoutMs)
                open.append(contentsOf: found.map { PortResult(port: $0, service: PortRangeScanner.serviceName($0)) })
                scanned += batch.count
                progress = Double(scanned) / Double(ports.count)
                status = "\(IPv4.string(ip)) · \(scanned) de \(ports.count) puertos"
            }

            let elapsed = Date().timeIntervalSince(started)
            status = Task.isCancelled
                ? "Detenido · \(open.count) abiertos de \(scanned) comprobados"
                : "\(IPv4.string(ip)) · \(open.count) puertos abiertos de \(ports.count) · \(String(format: "%.1f", elapsed)) s"
            isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Sube el límite de descriptores abiertos para poder lanzar lotes grandes de conexiones
    private static func raiseFileLimit() -> Int {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 64 }
        let wanted = min(limit.rlim_max, 4096)
        if limit.rlim_cur < wanted {
            limit.rlim_cur = wanted
            setrlimit(RLIMIT_NOFILE, &limit)
            getrlimit(RLIMIT_NOFILE, &limit)
        }
        // Dejar margen para el resto de la app
        return max(32, min(512, Int(limit.rlim_cur) - 128))
    }

    /// Conexiones TCP no bloqueantes en paralelo y un único poll() para todo el lote
    private static func scanBatch(_ ip: UInt32, _ ports: [UInt16], timeoutMs: Int32) async -> [UInt16] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var fds: [Int32] = []
                var pending: [pollfd] = []
                var pendingPorts: [UInt16] = []
                var open: [UInt16] = []

                for port in ports {
                    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
                    guard fd >= 0 else { continue }
                    fds.append(fd)
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
                    if rc == 0 {
                        open.append(port)
                    } else if errno == EINPROGRESS {
                        pending.append(pollfd(fd: fd, events: Int16(POLLOUT), revents: 0))
                        pendingPorts.append(port)
                    }
                }

                // Esperar hasta timeoutMs a que terminen los connect() pendientes
                let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
                var done = Set<Int>()
                while done.count < pending.count {
                    let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
                    guard remaining > 0, poll(&pending, nfds_t(pending.count), remaining) > 0 else { break }
                    for i in pending.indices where pending[i].revents != 0 && !done.contains(i) {
                        done.insert(i)
                        var error: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(pending[i].fd, SOL_SOCKET, SO_ERROR, &error, &len)
                        if error == 0 { open.append(pendingPorts[i]) }
                        pending[i].fd = -1  // poll() ignora descriptores negativos
                    }
                }

                fds.forEach { close($0) }
                continuation.resume(returning: open.sorted())
            }
        }
    }

    static func serviceName(_ port: UInt16) -> String? {
        if let known = NetworkProbe.commonPorts.first(where: { $0.0 == port }) { return known.1 }
        guard let entry = getservbyport(Int32(port.bigEndian), "tcp"), let name = entry.pointee.s_name else { return nil }
        return String(cString: name)
    }
}

// MARK: - DNS

enum DNSRecordType: String, CaseIterable, Identifiable {
    case A, AAAA, CNAME, MX, TXT, NS, SOA, PTR
    var id: String { rawValue }
}

struct DNSAnswer: Identifiable, Hashable {
    let name: String
    let ttl: Int
    let type: String
    let value: String
    var id: String { "\(name)|\(type)|\(value)" }
}

struct DNSResult: Identifiable {
    let server: String
    let serverLabel: String
    var status: String
    var answers: [DNSAnswer]
    var queryTimeMs: Int?
    var respondingServer: String?
    /// Al comparar: este servidor no resuelve lo que otros sí (AdGuard puede bloquear con NXDOMAIN)
    var differsFromOthers = false
    var id: String { server }

    var resolves: Bool { status == "NOERROR" && !answers.isEmpty && !isBlocked }

    var isBlocked: Bool {
        // Bloqueo típico de AdGuard/Pi-hole: responde 0.0.0.0 o ::
        answers.contains { $0.value == "0.0.0.0" || $0.value == "::" }
    }
}

enum DNSTool {
    static let systemServer = ""

    static func query(_ name: String, type: DNSRecordType, server: String, label: String) async -> DNSResult {
        var args = ["+noall", "+answer", "+stats", "+comments", "+time=2", "+tries=1"]
        if !server.isEmpty { args.append("@\(server)") }
        if type == .PTR {
            args += ["-x", name]
        } else {
            args += [name, type.rawValue]
        }
        let (_, output) = await NetworkProbe.run("/usr/bin/dig", args, timeout: 6)

        var result = DNSResult(server: server, serverLabel: label, status: "SIN RESPUESTA", answers: [])
        for line in output.split(separator: "\n") {
            if let m = line.firstMatch(of: #/status: (\w+)/#) {
                result.status = String(m.1)
            } else if let m = line.firstMatch(of: #/Query time: (\d+) msec/#) {
                result.queryTimeMs = Int(m.1)
            } else if let m = line.firstMatch(of: #/SERVER: ([^#\s]+)/#) {
                result.respondingServer = String(m.1)
            } else if line.contains("connection timed out") || line.contains("no servers could be reached") {
                result.status = "TIMEOUT"
            } else if !line.hasPrefix(";"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let parts = line.split(maxSplits: 4, whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count == 5, let ttl = Int(parts[1]) {
                    result.answers.append(DNSAnswer(name: String(parts[0]), ttl: ttl, type: String(parts[3]),
                                                    value: String(parts[4]).trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return result
    }
}
