//
//  ContentView.swift
//  WoL Manu
//
//  Created by WoL Manu on 28/9/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    @Environment(\.openWindow) private var openWindow
    @StateObject private var pingService = PingService()
    @StateObject private var wolService = WakeOnLANService()

    @State private var showingConfiguration = false
    @State private var showingDiagnostics = false

    private var config: DeviceConfiguration { configManager.configuration }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 16)

            PowerButton(
                status: pingService.deviceStatus,
                isProcessing: wolService.isProcessing,
                isEnabled: config.isValid
            ) {
                wolService.sendWakeOnLAN(configuration: config)
            }

            StatusPill(status: pingService.deviceStatus)
                .padding(.top, 22)

            Spacer(minLength: 16)

            footer
        }
        .padding(20)
        .frame(width: 340, height: 500)
        .background(BackgroundGradient(status: pingService.deviceStatus))
        .onAppear {
            updatePingService()
        }
        .onDisappear {
            pingService.stopMonitoring()
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(configuration: config)
        }
        .sheet(isPresented: $showingConfiguration) {
            ConfigurationView(
                configManager: configManager,
                pingService: pingService
            )
        }
        .onChange(of: config.ipAddress) {
            updatePingService()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.deviceName.isEmpty ? "Sin configurar" : config.deviceName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(config.deviceName.isEmpty ? .secondary : .primary)

                if !config.ipAddress.isEmpty {
                    Text(config.ipAddress)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                if !config.macAddress.isEmpty {
                    Text(config.macAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                showingDiagnostics = true
            } label: {
                Image(systemName: "stethoscope")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Diagnóstico de conexión")

            Button {
                openWindow(id: "scanner")
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Analizador de red")

            Button {
                showingConfiguration = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Configuración")
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            ModeChip(configuration: config)

            if !wolService.lastResult.isEmpty {
                ResultBanner(
                    message: wolService.lastResult,
                    success: wolService.lastSuccess,
                    isProcessing: wolService.isProcessing
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: wolService.lastResult)
    }

    // MARK: - Service Management

    private func updatePingService() {
        if config.isValid {
            pingService.startMonitoring(ipAddress: config.ipAddress)
        } else {
            pingService.stopMonitoring()
        }
    }
}

// MARK: - Power Button

private struct PowerButton: View {
    let status: DeviceStatus
    let isProcessing: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var pulse = false
    @State private var isHovering = false

    private var tint: Color {
        status == .online ? .green : .accentColor
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Halo
                Circle()
                    .fill(tint.opacity(isEnabled ? 0.35 : 0))
                    .blur(radius: 30)
                    .scaleEffect(isHovering ? 1.1 : 0.95)

                // Ondas mientras se envía
                if isProcessing {
                    ForEach(0..<2) { i in
                        Circle()
                            .stroke(tint.opacity(0.6), lineWidth: 2)
                            .scaleEffect(pulse ? 1.6 : 1)
                            .opacity(pulse ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double(i) * 0.7),
                                value: pulse
                            )
                    }
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.mix(with: .white, by: 0.15), tint.mix(with: .black, by: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: tint.opacity(0.5), radius: 16, y: 8)

                Image(systemName: "power")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: isProcessing)
            }
            .frame(width: 150, height: 150)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isProcessing)
        .saturation(isEnabled ? 1 : 0)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            withAnimation(.smooth) { isHovering = hovering }
        }
        .onChange(of: isProcessing) { _, processing in
            pulse = processing
        }
        .help(isEnabled ? "Encender equipo" : "Configura el dispositivo primero")
        .accessibilityLabel("Encender")
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Status & Mode

private struct StatusPill: View {
    let status: DeviceStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.color, radius: status == .online ? 4 : 0)
            Text(status.description)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .animation(.smooth, value: status)
    }
}

private struct ModeChip: View {
    let configuration: DeviceConfiguration

    var body: some View {
        Label {
            if configuration.vpnMode {
                Text("VPN · \(configuration.serverIP):\(String(configuration.serverPort))")
                    .monospacedDigit()
            } else {
                Text("Red local")
            }
        } icon: {
            Image(systemName: configuration.vpnMode ? "lock.shield.fill" : "wifi")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ResultBanner: View {
    let message: String
    let success: Bool?
    let isProcessing: Bool

    private var color: Color {
        switch success {
        case .some(true): .green
        case .some(false): .red
        case .none: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: success == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
            }
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Background

private struct BackgroundGradient: View {
    let status: DeviceStatus

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [(status == .online ? Color.green : .accentColor).opacity(0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.6), value: status)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConfigurationManager())
}
