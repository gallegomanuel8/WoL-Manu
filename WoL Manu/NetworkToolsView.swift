//
//  NetworkToolsView.swift
//  WoL Manu
//

import SwiftUI
import Charts
import AppKit

struct NetworkToolsView: View {
    @EnvironmentObject private var configManager: ConfigurationManager

    let initialTarget: String?

    @State private var target = ""
    @State private var tab: Tab = .ping

    enum Tab: Hashable {
        case ping, traceroute, ports, dns
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Destino", systemImage: "scope")
                    .foregroundStyle(.secondary)
                TextField("IP o nombre", text: $target, prompt: Text("192.168.1.1 o ejemplo.com"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(maxWidth: 320)
                Spacer()
                Picker("Herramienta", selection: $tab) {
                    Label("Ping", systemImage: "waveform.path.ecg").tag(Tab.ping)
                    Label("Traceroute", systemImage: "point.topleft.down.to.point.bottomright.curvepath").tag(Tab.traceroute)
                    Label("Puertos", systemImage: "door.left.hand.open").tag(Tab.ports)
                    Label("DNS", systemImage: "globe").tag(Tab.dns)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)
            .background(.bar)

            Divider()

            Group {
                switch tab {
                case .ping: PingToolView(target: target)
                case .traceroute: TracerouteToolView(target: target)
                case .ports: PortScanToolView(target: target)
                case .dns: DNSToolView(target: target)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if target.isEmpty {
                target = initialTarget ?? configManager.configuration.ipAddress
            }
        }
    }
}

// MARK: - Ping

private struct PingToolView: View {
    let target: String
    @StateObject private var monitor = PingMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if monitor.isRunning {
                    Button("Detener", systemImage: "stop.fill") { monitor.stop() }
                } else {
                    Button("Iniciar ping", systemImage: "play.fill") { monitor.start(target) }
                        .buttonStyle(.borderedProminent)
                        .disabled(target.isEmpty)
                }
                if let address = monitor.resolvedAddress, address != target {
                    Text(address).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let error = monitor.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                StatTile(title: "Enviados", value: "\(monitor.sent)")
                StatTile(title: "Pérdida", value: String(format: "%.0f %%", monitor.lossPercent),
                         tint: monitor.lossPercent > 5 ? .red : nil)
                StatTile(title: "Mín", value: ms(monitor.minMs))
                StatTile(title: "Media", value: ms(monitor.avgMs))
                StatTile(title: "Máx", value: ms(monitor.maxMs))
                StatTile(title: "Jitter", value: ms(monitor.jitterMs))
            }

            Chart {
                ForEach(monitor.samples) { sample in
                    if let value = sample.ms {
                        LineMark(x: .value("Secuencia", sample.seq), y: .value("ms", value))
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("Secuencia", sample.seq), y: .value("ms", value))
                            .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                             startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    } else {
                        RuleMark(x: .value("Secuencia", sample.seq))
                            .foregroundStyle(.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartYAxisLabel("ms")
            .chartXAxis(.hidden)
            .overlay {
                if monitor.samples.isEmpty {
                    Text(monitor.isRunning ? "Esperando respuestas…" : "Latencia en tiempo real. Las líneas rojas son paquetes perdidos.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onDisappear { monitor.stop() }
        .onChange(of: target) { monitor.stop() }
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value < 10 ? String(format: "%.1f ms", value) : "\(Int(value.rounded())) ms"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Traceroute

private struct TracerouteToolView: View {
    let target: String
    @StateObject private var runner = TracerouteRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if runner.isRunning {
                    Button("Detener", systemImage: "stop.fill") { runner.stop() }
                    ProgressView().controlSize(.small)
                } else {
                    Button("Trazar ruta", systemImage: "play.fill") { runner.start(target) }
                        .buttonStyle(.borderedProminent)
                        .disabled(target.isEmpty)
                }
                Spacer()
                if let error = runner.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }

            Table(runner.hops) {
                TableColumn("#") { Text("\($0.number)").monospacedDigit() }
                    .width(30)
                TableColumn("IP") { hop in
                    Text(hop.address ?? "*")
                        .font(.body.monospaced())
                        .foregroundStyle(hop.address == nil ? .tertiary : .primary)
                }
                .width(min: 110, ideal: 130)
                TableColumn("Nombre") { hop in
                    Text(hop.name ?? (hop.address == nil ? "Sin respuesta" : "—"))
                        .foregroundStyle(hop.name == nil ? .tertiary : .primary)
                }
                TableColumn("Tiempo") { hop in
                    Text(hop.ms.map { String(format: "%.1f ms", $0) } ?? "—").monospacedDigit()
                }
                .width(80)
            }
            .overlay {
                if runner.hops.isEmpty && !runner.isRunning {
                    Text("Muestra cada router por el que pasan los paquetes hasta el destino.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onDisappear { runner.stop() }
    }
}

// MARK: - Puertos

private struct PortScanToolView: View {
    let target: String
    @StateObject private var scanner = PortRangeScanner()

    @State private var preset: Preset = .wellKnown
    @State private var customFrom = "1"
    @State private var customTo = "1024"
    @State private var timeoutMs = 400.0

    enum Preset: String, CaseIterable, Identifiable {
        case wellKnown = "1–1024"
        case registered = "1–10000"
        case all = "Todos (1–65535)"
        case custom = "Personalizado"
        var id: String { rawValue }
    }

    private var range: ClosedRange<UInt16>? {
        switch preset {
        case .wellKnown: return 1...1024
        case .registered: return 1...10000
        case .all: return 1...65535
        case .custom:
            guard let a = UInt16(customFrom), let b = UInt16(customTo), a >= 1, a <= b else { return nil }
            return a...b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Puertos", selection: $preset) {
                    ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()

                if preset == .custom {
                    TextField("Desde", text: $customFrom).frame(width: 70)
                    Text("–")
                    TextField("Hasta", text: $customTo).frame(width: 70)
                }

                Picker("Espera", selection: $timeoutMs) {
                    Text("Rápido (LAN)").tag(250.0)
                    Text("Normal").tag(400.0)
                    Text("Lento (VPN/Internet)").tag(1000.0)
                }
                .fixedSize()
                .help("Tiempo de espera por conexión")

                Spacer()

                if scanner.isRunning {
                    Button("Detener", systemImage: "stop.fill") { scanner.stop() }
                } else {
                    Button("Escanear puertos", systemImage: "play.fill") {
                        if let range { scanner.start(host: target, range: range, timeoutMs: Int32(timeoutMs)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(target.isEmpty || range == nil)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                if scanner.isRunning {
                    ProgressView(value: scanner.progress).frame(width: 160)
                }
                Text(scanner.status).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            Table(scanner.open) {
                TableColumn("Puerto") { Text(String($0.port)).font(.body.monospacedDigit()) }
                    .width(70)
                TableColumn("Servicio") { result in
                    Text(result.service ?? "Desconocido")
                        .foregroundStyle(result.service == nil ? .secondary : .primary)
                }
                TableColumn("") { result in
                    if let url = url(for: result.port) {
                        Link("Abrir", destination: url)
                    }
                }
                .width(60)
            }
            .overlay {
                if scanner.open.isEmpty && !scanner.isRunning {
                    Text(scanner.status.isEmpty ? "Comprueba qué puertos TCP tiene abiertos el destino." : "Ningún puerto abierto.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Escanea solo equipos que sean tuyos o que tengas permiso para analizar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .onDisappear { scanner.stop() }
    }

    private func url(for port: UInt16) -> URL? {
        switch port {
        case 80, 8080, 8000, 5000, 3000, 8123, 9000: URL(string: "http://\(target):\(port)")
        case 443, 8443: URL(string: "https://\(target):\(port)")
        case 22: URL(string: "ssh://\(target)")
        case 445: URL(string: "smb://\(target)")
        case 5900: URL(string: "vnc://\(target)")
        default: nil
        }
    }
}

// MARK: - DNS

private struct DNSToolView: View {
    let target: String

    @State private var name = ""
    @State private var type: DNSRecordType = .A
    @State private var server = ""
    @State private var results: [DNSResult] = []
    @State private var isRunning = false
    @State private var gateway: String?

    private var servers: [(String, String)] {
        var list: [(String, String)] = [("", "Sistema")]
        if let gateway { list.append((gateway, "Router (\(gateway))")) }
        list += [("1.1.1.1", "Cloudflare"), ("8.8.8.8", "Google"), ("9.9.9.9", "Quad9")]
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Nombre", text: $name, prompt: Text(type == .PTR ? "IP para búsqueda inversa" : "ejemplo.com"))
                    .frame(minWidth: 200)
                    .onSubmit { run(compare: false) }
                Picker("Tipo", selection: $type) {
                    ForEach(DNSRecordType.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                TextField("Servidor", text: $server, prompt: Text("Sistema"))
                    .frame(width: 130)
                    .help("Vacío = DNS del sistema. Escribe p. ej. la IP de tu AdGuard o Pi-hole.")
                Menu {
                    ForEach(servers, id: \.0) { s in
                        Button(s.1) { server = s.0 }
                    }
                } label: {
                    Image(systemName: "server.rack")
                }
                .fixedSize()

                Spacer()

                Button("Consultar") { run(compare: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || isRunning)
                Button("Comparar servidores") { run(compare: true) }
                    .disabled(name.isEmpty || isRunning)
                    .help("Misma consulta contra el DNS del sistema, el router y DNS públicos")
            }
            .textFieldStyle(.roundedBorder)

            if isRunning {
                ProgressView().controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(results) { result in
                        DNSResultCard(result: result)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if results.isEmpty && !isRunning {
                    Text("Consulta registros DNS. «Comparar servidores» ayuda a ver si tu DNS bloquea o resuelve distinto.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
        }
        .padding()
        .task {
            // Una IP se consulta como búsqueda inversa (PTR); un nombre, como registro A
            if name.isEmpty {
                name = target
                if IPv4.parse(target) != nil { type = .PTR }
            }
            gateway = await NetworkProbe.defaultGateway().map(IPv4.string)
        }
    }

    private func run(compare: Bool) {
        let query = name.trimmingCharacters(in: .whitespaces)
        let targets = compare ? servers + (server.isEmpty || servers.contains { $0.0 == server } ? [] : [(server, server)])
                              : [(server, server.isEmpty ? "Sistema" : server)]
        isRunning = true
        results = []
        Task {
            await withTaskGroup(of: (Int, DNSResult).self) { group in
                for (i, s) in targets.enumerated() {
                    group.addTask { (i, await DNSTool.query(query, type: type, server: s.0, label: s.1)) }
                }
                var collected: [(Int, DNSResult)] = []
                for await r in group { collected.append(r) }
                var sorted = collected.sorted { $0.0 < $1.0 }.map(\.1)
                if sorted.count > 1, sorted.contains(where: \.resolves) {
                    for i in sorted.indices where !sorted[i].resolves && sorted[i].status != "TIMEOUT" {
                        sorted[i].differsFromOthers = true
                    }
                }
                results = sorted
            }
            isRunning = false
        }
    }
}

private struct DNSResultCard: View {
    let result: DNSResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.serverLabel).font(.headline)
                if let responding = result.respondingServer {
                    Text(responding).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if result.isBlocked {
                    Label("Bloqueado", systemImage: "hand.raised.fill").foregroundStyle(.orange).font(.caption.weight(.semibold))
                } else if result.differsFromOthers {
                    Label("Posible bloqueo", systemImage: "hand.raised").foregroundStyle(.orange).font(.caption.weight(.semibold))
                        .help("Otros servidores sí resuelven este nombre")
                }
                Text(result.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.status == "NOERROR" ? .green : .red)
                if let time = result.queryTimeMs {
                    Text("\(time) ms").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if result.answers.isEmpty {
                Text(result.status == "NOERROR" ? "Sin registros de ese tipo" : "Sin respuesta")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(result.answers) { answer in
                        GridRow {
                            Text(answer.type).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(answer.value).font(.callout.monospaced()).textSelection(.enabled)
                            Text("TTL \(answer.ttl)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}
