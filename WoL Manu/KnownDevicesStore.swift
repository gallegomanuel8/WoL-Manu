//
//  KnownDevicesStore.swift
//  WoL Manu
//
//  Recuerda las MAC vistas en escaneos anteriores para avisar de dispositivos nuevos.
//

import Foundation
import UserNotifications

struct KnownDevice: Codable {
    let mac: String
    let firstSeen: Date
    var lastSeen: Date
    var lastIP: String
    var vendor: String?
}

final class KnownDevicesStore {
    static let shared = KnownDevicesStore()

    private(set) var devices: [String: KnownDevice] = [:]
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WoL Manu", isDirectory: true)
        fileURL = support.appendingPathComponent("known_devices.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([KnownDevice].self, from: data) {
            devices = Dictionary(list.map { ($0.mac, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func firstSeen(_ mac: String?) -> Date? {
        mac.flatMap { devices[$0]?.firstSeen }
    }

    /// Registra los equipos del escaneo y devuelve las MAC que no se habían visto nunca.
    /// El primer escaneo solo crea la referencia: no hay "nuevos" hasta el siguiente.
    func register(_ hosts: [ScannedHost]) -> Set<String> {
        let isBaseline = devices.isEmpty
        var new: Set<String> = []
        let now = Date()

        for host in hosts where !host.isThisMac {
            guard let mac = host.mac else { continue }
            if var known = devices[mac] {
                known.lastSeen = now
                known.lastIP = host.ipString
                devices[mac] = known
            } else {
                devices[mac] = KnownDevice(mac: mac, firstSeen: now, lastSeen: now, lastIP: host.ipString, vendor: host.vendor)
                if !isBaseline { new.insert(mac) }
            }
        }
        save()
        return new
    }

    func forgetAll() {
        devices = [:]
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(devices.values))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[KnownDevices] Error guardando: \(error)")
        }
    }

    // MARK: - Notificaciones

    func notifyNewDevices(_ hosts: [ScannedHost]) {
        guard !hosts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            if hosts.count == 1, let host = hosts.first {
                content.title = "Nuevo dispositivo en la red"
                content.body = [host.ipString, host.hostname, host.vendor ?? host.kind.label, host.mac]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            } else {
                content.title = "\(hosts.count) dispositivos nuevos en la red"
                content.body = hosts.prefix(4).map { "\($0.ipString) (\($0.vendor ?? $0.kind.label))" }.joined(separator: ", ")
            }
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
