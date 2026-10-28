//
//  WoLAppIntents.swift
//  WoL Manu
//
//  Acciones para Atajos y Siri.
//

import AppIntents

struct WakeDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Encender equipo"
    static let description = IntentDescription("Envía Wake-on-LAN al equipo configurado en WoL Manu, en local o a través del servidor VPN.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ConfigurationManager().configuration
        guard config.isValid else {
            return .result(dialog: "WoL Manu no tiene ningún equipo configurado.")
        }
        let service = WakeOnLANService()
        let ok = await service.wake(configuration: config)
        let message = ok
            ? "Señal de encendido enviada a \(config.deviceName)."
            : "No se pudo encender \(config.deviceName): \(service.lastResult)"
        return .result(dialog: "\(message)")
    }
}

struct DeviceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Comprobar si el equipo está encendido"
    static let description = IntentDescription("Hace ping al equipo configurado en WoL Manu.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let config = ConfigurationManager().configuration
        guard let ip = IPv4.parse(config.ipAddress) else {
            return .result(value: false, dialog: "WoL Manu no tiene ningún equipo configurado.")
        }
        if let ms = await NetworkProbe.ping(ip) {
            return .result(value: true, dialog: "\(config.deviceName) está encendido (\(Int(ms.rounded())) ms).")
        }
        return .result(value: false, dialog: "\(config.deviceName) no responde: parece apagado.")
    }
}

struct WoLShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WakeDeviceIntent(),
            phrases: [
                "Enciende el equipo con \(.applicationName)",
                "Despierta el PC con \(.applicationName)",
                "Wake my computer with \(.applicationName)",
            ],
            shortTitle: "Encender equipo",
            systemImageName: "power"
        )
        AppShortcut(
            intent: DeviceStatusIntent(),
            phrases: [
                "¿Está encendido el equipo en \(.applicationName)?",
                "Is my computer on in \(.applicationName)",
            ],
            shortTitle: "Estado del equipo",
            systemImageName: "desktopcomputer"
        )
    }
}
