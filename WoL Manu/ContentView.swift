//
//  ContentView.swift
//  WoL Manu
//
//  Created by Manuel Alonso Rodriguez on 28/9/25.
//

import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var configManager = ConfigurationManager()
    @StateObject private var pingService = PingService()
    @StateObject private var wolService = WakeOnLANService()
    
    @State private var showingConfiguration = false
    @State private var showingWakeAlert = false
    @State private var wakeAlertMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            
            // App Title
            VStack(spacing: 5) {
                Image(systemName: "network")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Wake-on-LAN")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top)
            
            // Device Info Card
            GroupBox {
                VStack(spacing: 15) {
                    
                    // Device Name or Placeholder
                    HStack {
                        Text("Dispositivo:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(configManager.configuration.deviceName.isEmpty ? "No configurado" : configManager.configuration.deviceName)
                            .foregroundColor(configManager.configuration.deviceName.isEmpty ? .secondary : .primary)
                    }
                    
                    // IP Address
                    HStack {
                        Text("IP:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(configManager.configuration.ipAddress.isEmpty ? "No configurado" : configManager.configuration.ipAddress)
                            .foregroundColor(configManager.configuration.ipAddress.isEmpty ? .secondary : .primary)
                    }
                    
                    Divider()
                    
                    // Status Indicator
                    HStack {
                        Text("Estado:")
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pingService.deviceStatus.color)
                                .frame(width: 12, height: 12)
                            
                            Text(pingService.deviceStatus.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // VPN Mode Indicator
                    if configManager.configuration.vpnMode {
                        HStack {
                            Text("Modo:")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Image(systemName: "network.badge.shield.half.filled")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                
                                Text("VPN (\(configManager.configuration.serverIP))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Last WoL Result
                    if !wolService.lastResult.isEmpty {
                        HStack {
                            Text("Último envío:")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                if wolService.isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: wolService.lastResult.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(wolService.lastResult.contains("Error") ? .red : .green)
                                        .font(.caption)
                                }
                                
                                Text(wolService.lastResult)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            } label: {
                Text("Información del Dispositivo")
                    .font(.headline)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 15) {
                
                // Wake Up Button
                Button(action: {
                    sendWakeOnLANPacket()
                }) {
                    if wolService.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Enviando...")
                        }
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    } else {
                        Label("Encender", systemImage: "power")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!configManager.configuration.isValid || wolService.isProcessing)
                
                // Configuration Button
                Button(action: {
                    showingConfiguration = true
                }) {
                    Label("Configuración", systemImage: "gear")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350, height: 500)
        .onAppear {
            setupServices()
        }
        .onDisappear {
            print("[ContentView] View disappearing, cleaning up services")
            pingService.stopMonitoring()
            // El WakeOnLANService se limpiará automáticamente en su deinit
        }
        .sheet(isPresented: $showingConfiguration) {
            ConfigurationView(
                configManager: configManager,
                pingService: pingService
            )
        }
        .alert("Wake-on-LAN", isPresented: $showingWakeAlert) {
            Button("OK") { }
        } message: {
            Text(wakeAlertMessage)
        }
        .onChange(of: configManager.configuration.ipAddress) { _ in
            updatePingService()
        }
    }
    
    // MARK: - Service Management
    
    private func setupServices() {
        if configManager.configuration.isValid {
            pingService.startMonitoring(ipAddress: configManager.configuration.ipAddress)
        }
    }
    
    private func updatePingService() {
        if configManager.configuration.isValid {
            pingService.startMonitoring(ipAddress: configManager.configuration.ipAddress)
        } else {
            pingService.stopMonitoring()
        }
    }
    
    // MARK: - Wake-on-LAN Action
    
    private func sendWakeOnLANPacket() {
        guard configManager.configuration.isValid else {
            wakeAlertMessage = "Por favor, configura el dispositivo primero."
            showingWakeAlert = true
            return
        }
        
        // Usar el nuevo método dual (local/VPN)
        wolService.sendWakeOnLAN(configuration: configManager.configuration)
        
        let method = configManager.configuration.vpnMode ? "servidor VPN" : "red local"
        wakeAlertMessage = "Enviando Wake-on-LAN vía \(method) a \(configManager.configuration.deviceName)"
        showingWakeAlert = true
    }
}

#Preview {
    ContentView()
}
