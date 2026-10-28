//
//  MenuBarView.swift
//  WoL Manu
//
//  Acceso rápido desde la barra de menú: estado del equipo y botón de encendido.
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    @Environment(\.openWindow) private var openWindow
    @StateObject private var pingService = PingService()
    @StateObject private var wolService = WakeOnLANService()

    private var config: DeviceConfiguration { configManager.configuration }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(pingService.deviceStatus == .online ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.deviceName.isEmpty ? "Sin configurar" : config.deviceName)
                        .font(.headline)
                    HStack(spacing: 5) {
                        Circle().fill(pingService.deviceStatus.color).frame(width: 7, height: 7)
                        Text(pingService.deviceStatus.description)
                        Text("·")
                        Text(config.vpnMode ? "VPN" : "Red local")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                Task { await wolService.wake(configuration: config) }
            } label: {
                HStack {
                    if wolService.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "power")
                    }
                    Text(wolService.isProcessing ? "Enviando…" : "Encender")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!config.isValid || wolService.isProcessing)

            if !wolService.lastResult.isEmpty, !wolService.isProcessing {
                Label(wolService.lastResult, systemImage: wolService.lastSuccess == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(wolService.lastSuccess == true ? .green : .orange)
                    .lineLimit(2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuRow("Abrir WoL Manu", systemImage: "macwindow") { show("main") }
                MenuRow("Analizador de red", systemImage: "dot.radiowaves.left.and.right") { show("scanner") }
                MenuRow("Herramientas de red", systemImage: "wrench.and.screwdriver") { show("tools") }
                Divider().padding(.vertical, 4)
                MenuRow("Salir", systemImage: "xmark.circle") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            if config.isValid { pingService.startMonitoring(ipAddress: config.ipAddress) }
        }
        .onDisappear { pingService.stopMonitoring() }
    }

    private func show(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hovering ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
