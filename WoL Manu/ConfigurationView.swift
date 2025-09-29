//
//  ConfigurationView.swift
//  WoL Manu
//
//  Created by Manuel Alonso Rodriguez on 28/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationView: View {
    @ObservedObject var configManager: ConfigurationManager
    @ObservedObject var pingService: PingService
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var deviceName: String = ""
    @State private var ipAddress: String = ""
    @State private var macAddress: String = ""
    
    // VPN Configuration States
    @State private var vpnMode: Bool = false
    @State private var serverIP: String = ""
    @State private var apiKey: String = ""
    @State private var serverPort: String = "5000"
    @State private var fallbackLocal: Bool = false
    
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    
    // Import/Export states
    @State private var showingImportDialog = false
    @State private var showingExportDialog = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configuración del Dispositivo")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    
                    // Device Configuration Section
                    Group {
                        Text("Configuración del Dispositivo")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        // Device Name Field
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Nombre del Equipo")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Ej: PC Gaming", text: $deviceName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // IP Address Field
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Dirección IP")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Ej: 192.168.1.100", text: $ipAddress)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // MAC Address Field
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Dirección MAC")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Ej: AA:BB:CC:DD:EE:FF", text: $macAddress)
                                .textFieldStyle(.roundedBorder)
                                .textCase(.uppercase)
                        }
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // VPN Configuration Section
                    Group {
                        HStack {
                            Text("Configuración VPN")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $vpnMode)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        
                        if vpnMode {
                            VStack(alignment: .leading, spacing: 12) {
                                
                                // Server IP Field
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("IP del Servidor")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    TextField("Ej: 192.168.1.200", text: $serverIP)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                // Server Port Field
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Puerto del Servidor")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    TextField("5000", text: $serverPort)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                // API Key Field
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("API Key")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("(opcional)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    SecureField("Clave de autenticación", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                // Fallback Option
                                HStack {
                                    Toggle("Fallback local si falla VPN", isOn: $fallbackLocal)
                                        .font(.subheadline)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Import/Export Section
                    Group {
                        Text("Configuración")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            // Import Button
                            Button(action: {
                                showingImportDialog = true
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Importar")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            // Export Button
                            Button(action: {
                                showingExportDialog = true
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Exportar")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(!isFormValid)
                            
                            Spacer()
                        }
                        
                        Text("Importa o exporta la configuración completa del dispositivo y VPN")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 15) {
                
                // Cancel Button
                Button("Cancelar") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                // Save Button
                Button("Guardar") {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isFormValid)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 420, height: vpnMode ? 660 : 480)
        .onAppear {
            loadCurrentConfiguration()
        }
        .alert("Configuración", isPresented: $showingSaveAlert) {
            Button("OK") {
                if saveAlertMessage.contains("guardada") {
                    dismiss()
                }
            }
        } message: {
            Text(saveAlertMessage)
        }
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: ConfigurationDocument(configuration: configManager.configuration),
            contentType: .json,
            defaultFilename: "WoL_Config_\(configManager.configuration.deviceName.isEmpty ? "Dispositivo" : configManager.configuration.deviceName)"
        ) { result in
            handleExportResult(result)
        }
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        return !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Configuration Management
    
    private func loadCurrentConfiguration() {
        deviceName = configManager.configuration.deviceName
        ipAddress = configManager.configuration.ipAddress
        macAddress = configManager.configuration.macAddress
        
        // VPN Configuration
        vpnMode = configManager.configuration.vpnMode
        serverIP = configManager.configuration.serverIP
        apiKey = configManager.configuration.apiKey
        serverPort = String(configManager.configuration.serverPort)
        fallbackLocal = configManager.configuration.fallbackLocal
    }
    
    private func saveConfiguration() {
        // Validate form
        guard isFormValid else {
            saveAlertMessage = "Por favor, completa todos los campos."
            showingSaveAlert = true
            return
        }
        
        // Validate IP address format
        if !isValidIPAddress(ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)) {
            saveAlertMessage = "La dirección IP no tiene un formato válido."
            showingSaveAlert = true
            return
        }
        
        // Validate MAC address format
        if !isValidMACAddress(macAddress.trimmingCharacters(in: .whitespacesAndNewlines)) {
            saveAlertMessage = "La dirección MAC no tiene un formato válido. Use el formato AA:BB:CC:DD:EE:FF"
            showingSaveAlert = true
            return
        }
        
        // Validate VPN configuration if enabled
        if vpnMode {
            if !isValidIPAddress(serverIP.trimmingCharacters(in: .whitespacesAndNewlines)) {
                saveAlertMessage = "La IP del servidor no tiene un formato válido."
                showingSaveAlert = true
                return
            }
            
            guard let port = Int(serverPort.trimmingCharacters(in: .whitespacesAndNewlines)),
                  port > 0 && port <= 65535 else {
                saveAlertMessage = "El puerto del servidor debe ser un número entre 1 y 65535."
                showingSaveAlert = true
                return
            }
        }
        
        // Update configuration
        configManager.configuration = DeviceConfiguration(
            deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            ipAddress: ipAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            macAddress: formatMACAddress(macAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
            vpnMode: vpnMode,
            serverIP: serverIP.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            serverPort: Int(serverPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5000,
            fallbackLocal: fallbackLocal
        )
        
        // Save to file
        configManager.saveConfiguration()
        
        // Update ping service with new IP address
        pingService.updateIPAddress(configManager.configuration.ipAddress)
        
        saveAlertMessage = "Configuración guardada correctamente."
        showingSaveAlert = true
    }
    
    // MARK: - Validation Helpers
    
    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.components(separatedBy: ".")
        guard parts.count == 4 else { return false }
        
        for part in parts {
            guard let number = Int(part),
                  number >= 0 && number <= 255 else {
                return false
            }
        }
        return true
    }
    
    private func isValidMACAddress(_ mac: String) -> Bool {
        let cleanMAC = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard cleanMAC.count == 12 else { return false }
        
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        return cleanMAC.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) }
    }
    
    private func formatMACAddress(_ mac: String) -> String {
        let cleanMAC = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        
        guard cleanMAC.count == 12 else { return mac }
        
        var formatted = ""
        for i in stride(from: 0, to: 12, by: 2) {
            let startIndex = cleanMAC.index(cleanMAC.startIndex, offsetBy: i)
            let endIndex = cleanMAC.index(startIndex, offsetBy: 2)
            formatted += String(cleanMAC[startIndex..<endIndex])
            
            if i < 10 {
                formatted += ":"
            }
        }
        
        return formatted
    }
    
    // MARK: - Import/Export Handlers
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                try configManager.importConfiguration(from: url)
                loadCurrentConfiguration() // Refresh the UI with imported data
                saveAlertMessage = "Configuración importada correctamente desde \(url.lastPathComponent)"
                showingSaveAlert = true
            } catch {
                saveAlertMessage = "Error al importar configuración: \(error.localizedDescription)"
                showingSaveAlert = true
            }
            
        case .failure(let error):
            saveAlertMessage = "Error al seleccionar archivo: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            saveAlertMessage = "Configuración exportada correctamente a \(url.lastPathComponent)"
            showingSaveAlert = true
            
        case .failure(let error):
            saveAlertMessage = "Error al exportar configuración: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
}

// MARK: - Configuration Document for Export

struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let configuration: DeviceConfiguration
    
    init(configuration: DeviceConfiguration) {
        self.configuration = configuration
    }
    
    init(configuration: ReadConfiguration) throws {
        // This initializer is required by FileDocument but not used for export
        self.configuration = DeviceConfiguration()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self.configuration)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

struct ConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigurationView(
            configManager: ConfigurationManager(),
            pingService: PingService()
        )
    }
}