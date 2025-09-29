//
//  ConfigurationModel.swift
//  WoL Manu
//
//  Created by Manuel Alonso Rodriguez on 28/9/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Configuration Data Model
struct DeviceConfiguration: Codable {
    var deviceName: String
    var ipAddress: String
    var macAddress: String
    
    // VPN Configuration
    var vpnMode: Bool
    var serverIP: String
    var apiKey: String
    var serverPort: Int
    var fallbackLocal: Bool  // Fallback to local if VPN fails
    
    init() {
        self.deviceName = ""
        self.ipAddress = ""
        self.macAddress = ""
        self.vpnMode = false
        self.serverIP = "192.168.1.200"  // Default server IP
        self.apiKey = ""
        self.serverPort = 5000  // Default Flask port
        self.fallbackLocal = false
    }
    
    init(deviceName: String, ipAddress: String, macAddress: String, vpnMode: Bool = false, serverIP: String = "192.168.1.200", apiKey: String = "", serverPort: Int = 5000, fallbackLocal: Bool = false) {
        self.deviceName = deviceName
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.vpnMode = vpnMode
        self.serverIP = serverIP
        self.apiKey = apiKey
        self.serverPort = serverPort
        self.fallbackLocal = fallbackLocal
    }
    
    var isValid: Bool {
        let basicValid = !deviceName.isEmpty && !ipAddress.isEmpty && !macAddress.isEmpty
        if vpnMode {
            return basicValid && !serverIP.isEmpty && isValidIP(serverIP)
        }
        return basicValid
    }
    
    private func isValidIP(_ ip: String) -> Bool {
        // Basic IPv4 validation
        let components = ip.split(separator: ".").compactMap { Int($0) }
        return components.count == 4 && components.allSatisfy { $0 >= 0 && $0 <= 255 }
    }
}

// MARK: - Configuration Manager
@MainActor
class ConfigurationManager: ObservableObject {
    @Published var configuration = DeviceConfiguration()
    
    private let configFileURL: URL
    
    init() {
        // Path: ~/Projects/WoL Manu/config.json
        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects")
            .appendingPathComponent("WoL Manu")
        
        self.configFileURL = projectPath.appendingPathComponent("config.json")
        
        loadConfiguration()
    }
    
    func loadConfiguration() {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            print("Config file doesn't exist, using default configuration")
            return
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            let config = try JSONDecoder().decode(DeviceConfiguration.self, from: data)
            self.configuration = config
            print("Configuration loaded successfully")
        } catch {
            print("Error loading configuration: \(error)")
        }
    }
    
    func saveConfiguration() {
        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: configFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: configFileURL)
            print("Configuration saved successfully to: \(configFileURL.path)")
        } catch {
            print("Error saving configuration: \(error)")
        }
    }
    
    // MARK: - Import/Export Functions
    
    func exportConfiguration(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(configuration)
        try data.write(to: url)
        print("Configuration exported successfully to: \(url.path)")
    }
    
    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let importedConfig = try JSONDecoder().decode(DeviceConfiguration.self, from: data)
        
        // Validate imported configuration
        guard importedConfig.isValid else {
            throw ConfigurationError.invalidConfiguration
        }
        
        self.configuration = importedConfig
        // Also save to default location
        saveConfiguration()
        print("Configuration imported successfully from: \(url.path)")
    }
}

// MARK: - Configuration Errors
enum ConfigurationError: LocalizedError {
    case invalidConfiguration
    case fileNotReadable
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "La configuración importada no es válida"
        case .fileNotReadable:
            return "No se puede leer el archivo seleccionado"
        case .exportFailed:
            return "Error al exportar la configuración"
        }
    }
}
