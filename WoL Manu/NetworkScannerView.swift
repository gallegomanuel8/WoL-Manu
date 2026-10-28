//
//  NetworkScannerView.swift
//  WoL Manu
//

import SwiftUI
import AppKit

struct NetworkScannerView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    @StateObject private var scanner = NetworkScanner()

    @State private var source: Source = .custom
    @State private var rangeFrom = ""
    @State private var rangeTo = ""
    @State private var selection: ScannedHost.ID?
    @State private var sortOrder = [KeyPathComparator(\ScannedHost.ip)]
    @State private var searchText = ""
    @State private var showInspector = true
    @State private var hostPendingWoL: ScannedHost?

    enum Source: Hashable {
        case interface(String)
        case custom
    }

    // MARK: Derived

    private var target: ScanTarget? {
        switch source {
        case .interface(let name):
            return scanner.interfaces.first { $0.name == name }?.target
        case .custom:
            guard rangeError == nil, let r = IPv4.parseRange(from: rangeFrom, to: rangeTo) else { return nil }
            // Si el rango cae dentro de una red local, usar esa interfaz (MAC propia, "Este Mac")
            let iface = scanner.interfaces.first { !$0.isTunnel && $0.contains(r.first) && $0.contains(r.last) }
            let local = iface.flatMap { r.first...r.last ~= $0.address ? $0 : nil }
            return ScanTarget(first: r.first, last: r.last,
                              label: "\(IPv4.string(r.first)) – \(IPv4.string(r.last))",
                              interfaceName: iface?.name, localAddress: local?.address, localMAC: local?.mac)
        }
    }
    
    /// Motivo por el que el rango no es válido (nil si lo es o si aún está vacío)
    private var rangeError: String? {
        guard source == .custom, !rangeFrom.isEmpty, !rangeTo.isEmpty else { return nil }
        guard let r = IPv4.parseRange(from: rangeFrom, to: rangeTo) else { return "IP no válida" }
        guard r.first <= r.last else { return "«Desde» debe ser menor que «Hasta»" }
        guard Int(r.last - r.first) < ScanTarget.maxHosts else { return "Máximo \(ScanTarget.maxHosts) direcciones" }
        return nil
    }

    private var rows: [ScannedHost] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? scanner.hosts : scanner.hosts.filter {
            $0.ipString.contains(query)
                || ($0.hostname?.lowercased().contains(query) ?? false)
                || ($0.mac?.lowercased().contains(query) ?? false)
                || $0.openPorts.contains { $0.name.lowercased().contains(query) }
        }
        return filtered.sorted(using: sortOrder)
    }

    private var selectedHost: ScannedHost? {
        scanner.hosts.first { $0.id == selection }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            scanBar
            Divider()

            if scanner.hosts.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .frame(minWidth: 760, minHeight: 440)
        .searchable(text: $searchText, placement: .toolbar, prompt: "IP, nombre, MAC o servicio")
        .toolbar {
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Detalles", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let host = selectedHost {
                    HostDetailView(host: host, scanner: scanner, onUseForWoL: { hostPendingWoL = host })
                } else {
                    ContentUnavailableView("Ningún equipo seleccionado", systemImage: "cursorarrow.click",
                                           description: Text("Selecciona un equipo para ver sus detalles."))
                }
            }
            .inspectorColumnWidth(min: 250, ideal: 280, max: 360)
        }
        .confirmationDialog(
            "¿Usar este equipo para Wake-on-LAN?",
            isPresented: Binding(get: { hostPendingWoL != nil }, set: { if !$0 { hostPendingWoL = nil } }),
            presenting: hostPendingWoL
        ) { host in
            Button("Usar \(host.hostname ?? host.ipString)") { useForWoL(host) }
        } message: { host in
            Text("Se sustituirá el dispositivo configurado (\(configManager.configuration.deviceName)) por \(host.ipString) · \(host.mac ?? "")")
        }
        .onAppear(perform: chooseDefaultSource)
        .onChange(of: scanner.interfaces) {
            // Solo si la interfaz elegida ha desaparecido; un rango escrito a mano se respeta
            if case .interface(let name) = source, !scanner.interfaces.contains(where: { $0.name == name }) {
                chooseDefaultSource()
            }
        }
    }

    // MARK: Scan bar

    private var scanBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Red", selection: $source) {
                    ForEach(scanner.interfaces) { iface in
                        Text("\(iface.name) · \(iface.target.label)\(iface.isTunnel ? " (VPN)" : "")")
                            .tag(Source.interface(iface.name))
                    }
                    Divider()
                    Text("Rango de IPs").tag(Source.custom)
                }
                .labelsHidden()
                .frame(maxWidth: 260)

                if source == .custom {
                    HStack(spacing: 6) {
                        TextField("Desde", text: $rangeFrom, prompt: Text("192.168.1.1"))
                            .frame(width: 130)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Hasta", text: $rangeTo, prompt: Text("192.168.1.254"))
                            .frame(width: 130)
                            .help("IP completa o solo el último número (p. ej. 50)")
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(startScan)
                }

                Button {
                    scanner.refreshInterfaces()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Actualizar interfaces")

                Spacer()

                if scanner.isScanning {
                    Button("Detener", systemImage: "stop.fill", role: .cancel) { scanner.cancel() }
                } else {
                    Button("Escanear", systemImage: "dot.radiowaves.left.and.right", action: startScan)
                        .buttonStyle(.borderedProminent)
                        .disabled(target == nil)
                        .keyboardShortcut("r", modifiers: .command)
                }
            }

            HStack(spacing: 8) {
                if scanner.isScanning {
                    ProgressView(value: scanner.progress)
                        .frame(width: 140)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if let rangeError {
                    Label(rangeError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let target, source == .custom {
                    Text("\(target.count) direcciones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if target?.interfaceName == nil, target != nil {
                    Label("Fuera de la red local: sin MAC (ARP no cruza la VPN)", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var statusLine: String {
        var parts = [scanner.phase.label]
        if !scanner.hosts.isEmpty {
            parts.append("\(scanner.hosts.count) equipos")
        }
        if let t = scanner.lastTarget {
            parts.append(t.label)
        }
        if scanner.phase == .done, let date = scanner.lastScanDate {
            parts.append(date.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { host in
                Image(systemName: host.kind.symbol)
                    .foregroundStyle(host.isThisMac ? Color.accentColor : host.latencyMs == nil ? .secondary : .primary)
                    .help(host.kind.label)
            }
            .width(24)

            TableColumn("IP", value: \.ip) { host in
                Text(host.ipString).font(.body.monospacedDigit())
            }
            .width(min: 100, ideal: 115)

            TableColumn("Nombre", value: \.nameSort) { host in
                Text(host.hostname ?? "—")
                    .foregroundStyle(host.hostname == nil ? .tertiary : .primary)
            }
            .width(min: 120, ideal: 200)

            TableColumn("MAC", value: \.macSort) { host in
                HStack(spacing: 4) {
                    Text(host.mac ?? "—")
                        .font(.body.monospaced())
                        .foregroundStyle(host.mac == nil ? .tertiary : .primary)
                    if host.isPrivateMAC {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("MAC privada / aleatoria")
                    }
                }
            }
            .width(min: 185, ideal: 195)

            TableColumn("Latencia", value: \.latencySort) { host in
                LatencyText(host: host)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Servicios") { host in
                Text(host.openPorts.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu(forSelectionType: ScannedHost.ID.self) { ids in
            if let host = scanner.hosts.first(where: { ids.contains($0.id) }) {
                Button("Copiar IP") { copy(host.ipString) }
                if let mac = host.mac {
                    Button("Copiar MAC") { copy(mac) }
                }
                if let name = host.hostname {
                    Button("Copiar nombre") { copy(name) }
                }
                Divider()
                Button("Usar para Wake-on-LAN…") { hostPendingWoL = host }
                    .disabled(host.mac == nil || host.isThisMac)
            }
        }
    }

    private var emptyState: some View {
        Group {
            if scanner.isScanning {
                ContentUnavailableView {
                    Label(scanner.phase.label, systemImage: "dot.radiowaves.left.and.right")
                        .symbolEffect(.variableColor.iterative)
                } description: {
                    Text("Esto tarda unos segundos.")
                }
            } else {
                ContentUnavailableView {
                    Label("Analizador de red", systemImage: "network")
                } description: {
                    Text("Descubre los equipos de tu red: IP, MAC, nombre, latencia y servicios abiertos.")
                } actions: {
                    Button("Escanear", action: startScan)
                        .buttonStyle(.borderedProminent)
                        .disabled(target == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func chooseDefaultSource() {
        let deviceIP = IPv4.parse(configManager.configuration.ipAddress)
        // Rango por defecto: la /24 del dispositivo WoL (sin pisar lo que haya escrito el usuario)
        if rangeFrom.isEmpty, rangeTo.isEmpty {
            let base = (deviceIP ?? IPv4.parse("192.168.1.0")!) & 0xFFFF_FF00
            rangeFrom = IPv4.string(base | 1)
            rangeTo = IPv4.string(base | 254)
        }
        // Preferir la interfaz que esté en la red del dispositivo; si no (p. ej. por VPN), el rango
        if let deviceIP, let iface = scanner.interfaces.first(where: { !$0.isTunnel && $0.contains(deviceIP) }) {
            source = .interface(iface.name)
        } else {
            source = .custom
        }
    }

    private func startScan() {
        scanner.refreshInterfaces()
        guard let target else { return }
        selection = nil
        scanner.scan(target)
    }

    private func useForWoL(_ host: ScannedHost) {
        guard let mac = host.mac else { return }
        var config = configManager.configuration
        config.ipAddress = host.ipString
        config.macAddress = mac
        if let name = host.hostname {
            config.deviceName = String(name.split(separator: ".").first ?? Substring(name))
        }
        configManager.configuration = config
        configManager.saveConfiguration()
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Latency

private struct LatencyText: View {
    let host: ScannedHost

    var body: some View {
        if host.isThisMac {
            Text("local").foregroundStyle(.secondary)
        } else if let ms = host.latencyMs {
            HStack(spacing: 5) {
                Circle()
                    .fill(ms < 20 ? Color.green : ms < 100 ? .yellow : .orange)
                    .frame(width: 6, height: 6)
                Text(ms < 10 ? String(format: "%.1f ms", ms) : "\(Int(ms.rounded())) ms")
                    .monospacedDigit()
            }
        } else {
            Text("sin ping")
                .foregroundStyle(.tertiary)
                .help("No responde a ping, pero está en la tabla ARP (cortafuegos)")
        }
    }
}

// MARK: - Inspector

private struct HostDetailView: View {
    let host: ScannedHost
    @ObservedObject var scanner: NetworkScanner
    let onUseForWoL: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: host.kind.symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 14))
                    Text(host.hostname ?? host.ipString)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(host.kind.label)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    row("IP", host.ipString)
                    row("MAC", host.mac ?? "No disponible")
                    if host.isPrivateMAC {
                        row("", "MAC privada (aleatoria)")
                    }
                    row("Nombre", host.hostname ?? "No resuelto")
                    row("Latencia", host.isThisMac ? "—" : host.latencyMs.map { String(format: "%.1f ms", $0) } ?? "No responde a ping")
                }
                .font(.callout)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Servicios").font(.headline)
                        Spacer()
                        Button {
                            scanner.rescanPorts(of: host.id)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Volver a comprobar puertos")
                    }
                    if host.openPorts.isEmpty {
                        Text("Ningún puerto habitual abierto")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(host.openPorts, id: \.port) { port in
                                PortChip(host: host, port: port)
                            }
                        }
                    }
                }

                if !host.isThisMac {
                    Button(action: onUseForWoL) {
                        Label("Usar para Wake-on-LAN", systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(host.mac == nil)
                    .help(host.mac == nil ? "Hace falta la MAC: escanea desde la misma red local" : "")
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).font(label == "MAC" || label == "IP" ? .callout.monospaced() : .callout)
        }
    }
}

private struct PortChip: View {
    let host: ScannedHost
    let port: OpenPort

    private var url: URL? {
        switch port.port {
        case 80, 5000, 8080: URL(string: "http://\(host.ipString):\(port.port)")
        case 443: URL(string: "https://\(host.ipString)")
        case 22: URL(string: "ssh://\(host.ipString)")
        case 445: URL(string: "smb://\(host.ipString)")
        case 5900: URL(string: "vnc://\(host.ipString)")
        default: nil
        }
    }

    var body: some View {
        let chip = Text("\(port.name) · \(String(port.port))")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: .capsule)

        if let url {
            Link(destination: url) { chip }
                .help("Abrir \(url.absoluteString)")
        } else {
            chip
        }
    }
}

/// Distribuye los chips en filas que se ajustan al ancho disponible
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
