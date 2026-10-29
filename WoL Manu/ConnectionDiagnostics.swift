//
//  ConnectionDiagnostics.swift
//  WoL Manu
//
//  Comprueba paso a paso por qué podría fallar el encendido:
//  ruta / VPN → servidor → /health → /wake + API key → equipo destino.
//

import SwiftUI
import Combine

struct DiagnosticStep: Identifiable {
    enum Status { case pending, running, ok, warning, failed, skipped }

    let id: Int
    let title: String
    var status: Status = .pending
    var detail = ""
}

final class ConnectionDiagnostics: ObservableObject {
    @Published private(set) var steps: [DiagnosticStep] = []
    @Published private(set) var isRunning = false

    var summary: (String, DiagnosticStep.Status)? {
        guard !isRunning, !steps.isEmpty else { return nil }
        if let failed = steps.first(where: { $0.status == .failed }) {
            return ("Falla: \(failed.title.lowercased())", .failed)
        }
        if steps.contains(where: { $0.status == .warning }) {
            return ("Funciona, con avisos", .warning)
        }
        return ("Todo correcto: el encendido debería funcionar", .ok)
    }

    func run(_ config: DeviceConfiguration) {
        guard !isRunning else { return }
        isRunning = true
        Task {
            if config.vpnMode {
                await runRelay(config)
            } else {
                await runLocal(config)
            }
            isRunning = false
        }
    }

    // MARK: Modo VPN / servidor relay

    private func runRelay(_ c: DeviceConfiguration) async {
        steps = [
            DiagnosticStep(id: 0, title: "Ruta hasta el servidor"),
            DiagnosticStep(id: 1, title: "Servidor alcanzable"),
            DiagnosticStep(id: 2, title: "Servicio WoL (/health)"),
            DiagnosticStep(id: 3, title: "Endpoint /wake y API key"),
            DiagnosticStep(id: 4, title: "Equipo destino"),
        ]
        let base = "http://\(c.serverIP):\(c.serverPort)"

        // 0. Ruta
        update(0, .running)
        let route = await routeInfo(to: c.serverIP)
        let wireguard = await wireGuardStatus()
        switch route.kind {
        case .tunnel:
            update(0, .ok, "Por túnel VPN (\(route.interface))" + (wireguard.map { " · WireGuard: \($0)" } ?? ""))
        case .local:
            update(0, .ok, "Mismo segmento de red local (\(route.interface)); la VPN no hace falta")
        case .defaultRoute:
            update(0, .failed, "Sin ruta hacia \(c.serverIP): el tráfico sale por la conexión normal (\(route.interface)). "
                   + (wireguard.map { "WireGuard: \($0). " } ?? "") + "¿Está conectada la VPN?")
        case .none:
            update(0, .failed, "No hay ninguna ruta hacia \(c.serverIP)")
        }

        // 1. TCP
        update(1, .running)
        guard let serverIP = IPv4.parse(c.serverIP) else {
            update(1, .failed, "IP del servidor no válida")
            return skipRemaining(from: 2)
        }
        let start = Date()
        let reachable = await Task.detached { NetworkProbe.isPortOpen(serverIP, UInt16(clamping: c.serverPort), timeoutMs: 3000) }.value
        let tcpMs = Date().timeIntervalSince(start) * 1000
        guard reachable else {
            update(1, .failed, "No responde en \(c.serverIP):\(c.serverPort). Servidor apagado, servicio parado o puerto bloqueado.")
            return skipRemaining(from: 2)
        }
        update(1, .ok, String(format: "Puerto %d abierto · %.0f ms", c.serverPort, tcpMs))

        // 2. /health
        update(2, .running)
        let (healthCode, healthJSON) = await http("GET", "\(base)/health", apiKey: nil)
        if healthCode == 200, let status = healthJSON?["status"] as? String, ["ok", "healthy"].contains(status) {
            var detail = "Responde «\(status)»"
            if let server = healthJSON?["server"] as? String { detail += " · \(server)" }
            if let uptime = healthJSON?["uptime_seconds"] as? Int { detail += " · activo \(Self.duration(uptime))" }
            if let packets = healthJSON?["magic_packets_sent"] as? Int { detail += " · \(packets) paquetes enviados" }
            update(2, .ok, detail)
        } else if let healthCode {
            update(2, .failed, "Respuesta inesperada (HTTP \(healthCode)). ¿Es el servidor WoL correcto?")
        } else {
            update(2, .failed, "Sin respuesta HTTP")
        }

        // 3. /wake sin MAC: el servidor contesta 400 sin enviar nada, lo que basta para validar endpoint y clave
        update(3, .running)
        let (withKey, _) = await http("POST", "\(base)/wake", apiKey: c.apiKey.isEmpty ? nil : c.apiKey, body: [:])
        switch withKey {
        case 400:
            let (withoutKey, _) = await http("POST", "\(base)/wake", apiKey: nil, body: [:])
            if withoutKey == 401 || withoutKey == 403 {
                update(3, .ok, "Endpoint correcto y API key aceptada")
            } else {
                update(3, .warning, "Endpoint correcto, pero el servidor no exige API key: cualquiera con acceso a la red puede encender equipos")
            }
        case 401, 403:
            update(3, .failed, "El servidor rechaza la API key (HTTP \(withKey!)). Revísala en Configuración.")
        case 404:
            // Servidor Flask antiguo (wol-server/app.py): mismo protocolo en /wol
            let (legacy, _) = await http("POST", "\(base)/wol", apiKey: c.apiKey.isEmpty ? nil : c.apiKey, body: [:])
            switch legacy {
            case 400:
                update(3, .ok, "Servidor Flask (endpoint /wol): compatible")
            case 401, 403:
                update(3, .failed, "El servidor (/wol) rechaza la API key. Revísala en Configuración.")
            default:
                update(3, .failed, "El servidor no tiene /wake ni /wol (HTTP 404). ¿Es el servidor WoL correcto?")
            }
        case let code?:
            update(3, .warning, "Respuesta inesperada de /wake (HTTP \(code))")
        case nil:
            update(3, .failed, "Sin respuesta de /wake")
        }

        // 4. Equipo
        await checkDevice(4, c)
    }

    // MARK: Modo local

    private func runLocal(_ c: DeviceConfiguration) async {
        steps = [
            DiagnosticStep(id: 0, title: "Misma red que el equipo"),
            DiagnosticStep(id: 1, title: "Equipo destino"),
        ]
        update(0, .running)
        let route = await routeInfo(to: c.ipAddress)
        if route.kind == .local {
            update(0, .ok, "Conectado a la red del equipo (\(route.interface)); el broadcast llegará")
        } else {
            update(0, .failed, "Este Mac no está en la red de \(c.ipAddress) (sale por \(route.interface.isEmpty ? "—" : route.interface)). "
                   + "Fuera de casa activa el modo VPN en Configuración.")
        }
        await checkDevice(1, c)
    }

    private func checkDevice(_ index: Int, _ c: DeviceConfiguration) async {
        update(index, .running)
        guard let ip = IPv4.parse(c.ipAddress) else {
            update(index, .failed, "IP del equipo no válida")
            return
        }
        if let ms = await NetworkProbe.ping(ip) {
            update(index, .ok, String(format: "%@ ya está encendido (%.0f ms)", c.deviceName, ms))
        } else {
            update(index, .warning, "\(c.deviceName) no responde a ping: apagado (normal antes de encenderlo) o con el ping bloqueado")
        }
    }

    // MARK: Helpers

    private func update(_ index: Int, _ status: DiagnosticStep.Status, _ detail: String = "") {
        guard steps.indices.contains(index) else { return }
        steps[index].status = status
        if !detail.isEmpty || status == .running { steps[index].detail = detail }
    }

    private func skipRemaining(from index: Int) {
        for i in index..<steps.count {
            steps[i].status = .skipped
            steps[i].detail = "No comprobado"
        }
    }

    private enum RouteKind { case tunnel, local, defaultRoute, none }

    private func routeInfo(to host: String) async -> (kind: RouteKind, interface: String) {
        let (status, output) = await NetworkProbe.run("/sbin/route", ["-n", "get", host], timeout: 3)
        guard status == 0, let m = output.firstMatch(of: #/interface: (\S+)/#) else { return (.none, "") }
        let iface = String(m.1)
        if iface.hasPrefix("utun") || iface.hasPrefix("wg") || iface.hasPrefix("ppp") || iface.hasPrefix("ipsec") {
            return (.tunnel, iface)
        }
        // Sin "gateway:" la ruta es directa (mismo segmento)
        if !output.contains("gateway:") { return (.local, iface) }
        let isDefault = output.contains("destination: default")
        return (isDefault ? .defaultRoute : .local, iface)
    }

    private func wireGuardStatus() async -> String? {
        let (_, output) = await NetworkProbe.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 3)
        for line in output.split(separator: "\n") where line.localizedCaseInsensitiveContains("wireguard") {
            if line.contains("(Connected)") { return "conectado" }
            if line.contains("(Connecting)") { return "conectando" }
            if line.contains("(Disconnected)") { return "desconectado" }
        }
        return nil
    }

    private func http(_ method: String, _ urlString: String, apiKey: String?, body: [String: Any]? = nil) async -> (Int?, [String: Any]?) {
        guard let url = URL(string: urlString) else { return (nil, nil) }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = method
        request.setValue("WoLManu/1.3", forHTTPHeaderField: "User-Agent")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return ((response as? HTTPURLResponse)?.statusCode, json)
        } catch {
            return (nil, nil)
        }
    }

    private static func duration(_ seconds: Int) -> String {
        let d = seconds / 86400, h = seconds % 86400 / 3600, m = seconds % 3600 / 60
        if d > 0 { return "\(d) d \(h) h" }
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }
}

// MARK: - Vista

struct DiagnosticsView: View {
    let configuration: DeviceConfiguration
    @StateObject private var diagnostics = ConnectionDiagnostics()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnóstico de conexión").font(.title2.weight(.bold))
                    Text(configuration.vpnMode
                         ? "Servidor \(configuration.serverIP):\(String(configuration.serverPort)) → \(configuration.deviceName)"
                         : "Red local → \(configuration.deviceName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(diagnostics.steps) { step in
                    StepRow(step: step)
                    if step.id != diagnostics.steps.last?.id { Divider().padding(.leading, 40) }
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))

            if let (text, status) = diagnostics.summary {
                Label(text, systemImage: status == .ok ? "checkmark.seal.fill" : status == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(status == .ok ? .green : status == .warning ? .orange : .red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Volver a probar") { diagnostics.run(configuration) }
                    .disabled(diagnostics.isRunning)
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 500, height: configuration.vpnMode ? 520 : 360)
        .onAppear { diagnostics.run(configuration) }
    }
}

private struct StepRow: View {
    let step: DiagnosticStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.body.weight(.medium))
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }
}
