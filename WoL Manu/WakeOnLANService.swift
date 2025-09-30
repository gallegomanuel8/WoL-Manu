//
//  WakeOnLANService.swift
//  WoL Manu
//
//  Created by Manuel Alonso Rodriguez on 28/9/25.
//

import Foundation
import SwiftUI
import Combine
import Darwin
import Network

// MARK: - WoL Log Entry
struct WoLLogEntry {
    let timestamp: Date
    let method: String
    let success: Bool
    let message: String
    let httpCode: Int?
}

class WakeOnLANService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var lastResult: String = ""
    
    // MARK: - Private Properties
    private var logHistory: [WoLLogEntry] = []
    private let maxLogEntries = 10
    
    // MARK: - API pública
    
    /// Método principal para enviar Wake-on-LAN con modo dual (local/VPN)
    /// - Parameters:
    ///   - configuration: Configuración completa del dispositivo y VPN
    func sendWakeOnLAN(configuration: DeviceConfiguration) {
        guard configuration.isValid else {
            let message = "Configuración inválida"
            print("[WoLService] Error: \(message)")
            logResult(method: "Validation", success: false, message: message)
            return
        }
        
        isProcessing = true
        lastResult = "Procesando..."
        
        if configuration.vpnMode {
            sendViaVPN(configuration: configuration)
        } else {
            sendLocalWakeOnLAN(macAddress: configuration.macAddress, targetIP: configuration.ipAddress)
        }
        
        isProcessing = false
    }
    
    // MARK: - VPN Mode Implementation
    
    private func sendViaVPN(configuration: DeviceConfiguration) {
        print("[WoLService] Modo VPN activado - enviando vía servidor \(configuration.serverIP):\(configuration.serverPort)")
        
        Task {
            do {
                // 1. Health Check
                let healthOK = try await performHealthCheck(configuration: configuration)
                guard healthOK else {
                    let message = "Health check fallido"
                    await MainActor.run {
                        handleVPNFailure(configuration: configuration, message: message)
                    }
                    return
                }
                
                // 2. Send WoL Request
                let success = try await sendWoLRequest(configuration: configuration)
                
                await MainActor.run {
                    if success {
                        let message = "Wake-on-LAN enviado vía servidor"
                        print("[WoLService] \(message)")
                        lastResult = message
                        logResult(method: "VPN", success: true, message: message, httpCode: 200)
                    } else {
                        handleVPNFailure(configuration: configuration, message: "Error en petición al servidor")
                    }
                }
            } catch {
                await MainActor.run {
                    let message = "Error de conexión: \(error.localizedDescription)"
                    handleVPNFailure(configuration: configuration, message: message)
                }
            }
        }
    }
    
    // MARK: - HTTP Methods
    
    private func performHealthCheck(configuration: DeviceConfiguration) async throws -> Bool {
        let url = URL(string: "http://\(configuration.serverIP):\(configuration.serverPort)/health")!
        
        // MEJORA #5: URLSession con configuración optimizada
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0  // Aumentado de 5s
        sessionConfig.timeoutIntervalForResource = 15.0
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WoLManu/1.3", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[WoLService] Health check - respuesta no HTTP")
                return false
            }
            
            print("[WoLService] Health check - HTTP \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = jsonResponse["status"] as? String,
                   status == "ok" {
                    print("[WoLService] Health check OK - servidor responde correctamente")
                    return true
                }
                print("[WoLService] Health check - respuesta JSON inválida")
                return false
            }
            
            print("[WoLService] Health check failed - HTTP \(httpResponse.statusCode)")
            return false
            
        } catch {
            print("[WoLService] Health check error: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func sendWoLRequest(configuration: DeviceConfiguration) async throws -> Bool {
        let url = URL(string: "http://\(configuration.serverIP):\(configuration.serverPort)/wol")!
        
        // MEJORA #5: URLSession con configuración optimizada
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0  // Aumentado de 5s
        sessionConfig.timeoutIntervalForResource = 25.0
        sessionConfig.waitsForConnectivity = false
        sessionConfig.allowsCellularAccess = false  // Solo WiFi/Ethernet
        let session = URLSession(configuration: sessionConfig)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WoLManu/1.3", forHTTPHeaderField: "User-Agent")
        
        // Add API Key if configured
        if !configuration.apiKey.isEmpty {
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        // Create request body
        let requestBody: [String: Any] = [
            "mac": configuration.macAddress,
            "ip": configuration.ipAddress,
            "name": configuration.deviceName
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // MEJORA #5: Retry logic mejorado con exponential backoff y jitter
        var lastError: Error?
        var baseDelay: Double = 0.8  // Aumentado
        
        let maxRetries = 4  // Aumentado de 3 a 4
        for attempt in 1...maxRetries {
            do {
                print("[WoLService] Enviando WoL request (intento \(attempt)/\(maxRetries))")
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[WoLService] Respuesta no HTTP")
                    throw URLError(.badServerResponse)
                }
                
                let httpCode = httpResponse.statusCode
                print("[WoLService] Servidor responde HTTP \(httpCode)")
                
                // Handle different response codes
                switch httpCode {
                case 200, 202, 204:
                    if httpCode == 200 {
                        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let status = jsonResponse["status"] as? String,
                           status == "sent" {
                            return true
                        }
                    }
                    return true // Accept 202/204 as success
                    
                case 401, 403:
                    let message = "Autorización fallida (X-API-Key incorrecta)"
                    print("[WoLService] \(message)")
                    await MainActor.run {
                        logResult(method: "VPN", success: false, message: message, httpCode: httpCode)
                    }
                    return false
                    
                case 429:
                    // MEJORA #5: Manejo específico de rate limiting
                    let message = "Rate limit alcanzado"
                    print("[WoLService] \(message) - Intento \(attempt)/\(maxRetries)")
                    if attempt == maxRetries {
                        await MainActor.run {
                            logResult(method: "VPN", success: false, message: message, httpCode: httpCode)
                        }
                        return false
                    }
                    // Continuar con retry pero con delay mayor para rate limiting
                    
                case 400...499:
                    let message = "Error en petición: \(httpCode)"
                    print("[WoLService] \(message)")
                    await MainActor.run {
                        logResult(method: "VPN", success: false, message: message, httpCode: httpCode)
                    }
                    return false
                    
                case 500...599:
                    let message = "Error de servidor: \(httpCode)"
                    print("[WoLService] \(message) - Intento \(attempt)/3")
                    if attempt == 3 {
                        await MainActor.run {
                            logResult(method: "VPN", success: false, message: message, httpCode: httpCode)
                        }
                        return false
                    }
                    // Continue to retry for 5xx errors
                    
                default:
                    let message = "Respuesta HTTP inesperada: \(httpCode)"
                    print("[WoLService] \(message)")
                    await MainActor.run {
                        logResult(method: "VPN", success: false, message: message, httpCode: httpCode)
                    }
                    return false
                }
                
            } catch {
                lastError = error
                print("[WoLService] Error en intento \(attempt): \(error.localizedDescription)")
                if attempt < maxRetries {
                    // MEJORA #5: Backoff exponencial con jitter para evitar thundering herd
                    let isRateLimit = (error as? URLError)?.code == URLError.Code.timedOut || 
                                     String(describing: error).contains("429")
                    
                    let multiplier = isRateLimit ? 3.0 : 1.0  // Delay mayor para rate limiting
                    let exponentialDelay = min(pow(2.0, Double(attempt - 1)) * baseDelay * multiplier, 15.0)
                    let jitter = Double.random(in: 0.1...0.4) * exponentialDelay  // 10-40% jitter
                    let totalDelay = exponentialDelay + jitter
                    
                    print("[WoLService] Esperando \(String(format: "%.1f", totalDelay))s antes del siguiente intento...")
                    try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                } else {
                    print("[WoLService] Todos los intentos fallaron tras \(maxRetries) reintentos")
                    throw error
                }
            }
        }
        
        throw lastError ?? URLError(.unknown)
    }
    
    // MARK: - Failure Handling
    
    private func handleVPNFailure(configuration: DeviceConfiguration, message: String) {
        print("[WoLService] VPN Error: \(message)")
        lastResult = "Error VPN: \(message)"
        logResult(method: "VPN", success: false, message: message)
        
        if configuration.fallbackLocal {
            print("[WoLService] Usando fallback local")
            lastResult = "VPN falló - usando método local"
            sendLocalWakeOnLAN(macAddress: configuration.macAddress, targetIP: configuration.ipAddress)
        }
    }
    
    // MARK: - Local WoL Implementation
    
    private func sendLocalWakeOnLAN(macAddress: String, targetIP: String?) {
        print("[WoLService] Modo local activado")
        
        guard let macBytes = parseMACAddress(macAddress) else {
            let message = "MAC inválida: \(macAddress)"
            print("[WoLService] Error: \(message)")
            lastResult = "Error: \(message)"
            logResult(method: "Local", success: false, message: message)
            return
        }
        
        guard let magicPacket = buildMagicPacket(macBytes: macBytes) else {
            let message = "No se pudo construir el paquete mágico"
            print("[WoLService] Error: \(message)")
            lastResult = "Error: \(message)"
            logResult(method: "Local", success: false, message: message)
            return
        }
        
        print("[WoLService] Magic Packet construido: \(magicPacket.count) bytes")
        
        var successCount = 0
        let ports: [UInt16] = [9, 7]
        
        // Broadcast global
        for port in ports {
            if sendUDPToAddress(data: magicPacket, address: "255.255.255.255", port: port) {
                print("[WoLService] ✅ Enviado a broadcast global 255.255.255.255:\(port)")
                successCount += 1
            }
        }
        
        // Envío dirigido si se proporciona IP
        if let targetIP = targetIP, !targetIP.isEmpty {
            for port in ports {
                if sendUDPToAddress(data: magicPacket, address: targetIP, port: port) {
                    print("[WoLService] ✅ Enviado dirigido a \(targetIP):\(port)")
                    successCount += 1
                }
            }
        }
        
        let message = "\(successCount) paquetes enviados localmente"
        print("[WoLService] \(message)")
        lastResult = successCount > 0 ? "Wake-on-LAN enviado localmente" : "Error enviando localmente"
        logResult(method: "Local", success: successCount > 0, message: message)
    }
    
    // MARK: - Logging
    
    private func logResult(method: String, success: Bool, message: String, httpCode: Int? = nil) {
        let entry = WoLLogEntry(
            timestamp: Date(),
            method: method,
            success: success,
            message: message,
            httpCode: httpCode
        )
        
        logHistory.append(entry)
        if logHistory.count > maxLogEntries {
            logHistory.removeFirst()
        }
    }
    
    // MARK: - Public Log Access
    
    func getLogHistory() -> [WoLLogEntry] {
        return logHistory
    }
    
    /// Método legacy (conservado por compatibilidad)
    func sendWakeOnLANPacket(to macAddress: String, targetIP: String? = nil) {
        print("[WoLService] Warning: Usando método legacy")
        sendLocalWakeOnLAN(macAddress: macAddress, targetIP: targetIP)
    }
    
    // MARK: - Construcción del paquete
    
    /// Convierte una MAC en bytes
    internal func parseMACAddress(_ macAddress: String) -> [UInt8]? {
        let cleanMAC = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        
        guard cleanMAC.count == 12 else { return nil }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let startIndex = cleanMAC.index(cleanMAC.startIndex, offsetBy: i)
            let endIndex = cleanMAC.index(startIndex, offsetBy: 2)
            let hexString = String(cleanMAC[startIndex..<endIndex])
            guard let byte = UInt8(hexString, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes.count == 6 ? bytes : nil
    }
    
    /// 6 bytes 0xFF + 16 repeticiones de la MAC
    internal func buildMagicPacket(macBytes: [UInt8]) -> Data? {
        guard macBytes.count == 6 else { return nil }
        var packet = Data()
        for _ in 0..<6 { packet.append(0xFF) }
        for _ in 0..<16 { packet.append(contentsOf: macBytes) }
        return packet
    }
    
    // MARK: - Envío por UDP (broadcast)
    
    /// Obtiene las direcciones de broadcast IPv4 de las interfaces UP no loopback
    private func getBroadcastAddresses() -> [in_addr] {
        var result: [in_addr] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return result }
        defer { freeifaddrs(ifaddrPtr) }
        
        var ptr = first
        while true {
            let ifa = ptr.pointee
            
            // Solo IPv4
            if ifa.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET) {
                let flags = Int32(ifa.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                let supportsBroadcast = (flags & IFF_BROADCAST) != 0
                
                if isUp && !isLoopback && supportsBroadcast,
                   let addrPtr = ifa.ifa_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0 }),
                   let maskPtr = ifa.ifa_netmask?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0 }) {
                    
                    // Dirección y máscara en orden de red
                    let ip = addrPtr.pointee.sin_addr.s_addr
                    let mask = maskPtr.pointee.sin_addr.s_addr
                    // Broadcast = (IP & MASK) | ~MASK
                    let broadcast = in_addr(s_addr: (ip & mask) | ~mask)
                    result.append(broadcast)
                }
            }
            
            if ptr.pointee.ifa_next == nil { break }
            ptr = ptr.pointee.ifa_next!
        }
        
        // Evitar duplicados
        var seen = Set<UInt32>()
        result = result.filter { seen.insert($0.s_addr).inserted }
        return result
    }
    
    /// Envía un datagrama UDP a una dirección de broadcast concreta
    private func sendUDPBroadcast(data: Data, to broadcast: in_addr, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if fd < 0 {
            perror("socket")
            return false
        }
        defer { close(fd) }
        
        // Permitir broadcast
        var yes: Int32 = 1
        if setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) < 0 {
            perror("setsockopt(SO_BROADCAST)")
            return false
        }
        // Opcional: reutilizar dirección
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = broadcast
        
        let sent: Int = data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress, rawBuf.count > 0 else { return -1 }
            var sa = unsafeBitCast(addr, to: sockaddr.self)
            return withUnsafePointer(to: &sa) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPtr in
                    sendto(fd, base, rawBuf.count, 0, reboundPtr, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
        }
        
        if sent < 0 {
            perror("sendto")
            return false
        }
        return sent == data.count
    }
    
    // MARK: - Utilidades
    
    private func string(from addr: in_addr) -> String {
        var addr = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
    
    // MARK: - Nuevos métodos auxiliares
    
    /// Envía UDP a una dirección IP específica (puede ser broadcast o dirigida)
    private func sendUDPToAddress(data: Data, address: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if fd < 0 {
            print("[WoLService] Error creating socket: \(String(cString: strerror(errno)))")
            return false
        }
        
        // Permitir broadcast
        var yes: Int32 = 1
        if setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) < 0 {
            print("[WoLService] Error setting SO_BROADCAST: \(String(cString: strerror(errno)))")
            close(fd)
            return false
        }
        
        // Reutilizar dirección
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        
        // Convertir IP string a in_addr
        if inet_pton(AF_INET, address, &addr.sin_addr) != 1 {
            print("[WoLService] Invalid IP address format: \(address)")
            close(fd)
            return false
        }
        
        let sent: Int = data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress, rawBuf.count > 0 else { return -1 }
            var sa = unsafeBitCast(addr, to: sockaddr.self)
            return withUnsafePointer(to: &sa) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPtr in
                    sendto(fd, base, rawBuf.count, 0, reboundPtr, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
        }
        
        let success = sent == data.count
        if !success {
            print("[WoLService] Error sending UDP packet: \(String(cString: strerror(errno)))")
        }
        
        // MEJORA #6: Delay explícito antes de cerrar socket para asegurar transmisión
        usleep(300_000) // 300ms delay
        close(fd)
        
        return success
    }
    
    /// Calcula la dirección de broadcast de una subnet dada una IP
    /// Asume máscara /24 (255.255.255.0) que es la más común
    private func calculateSubnetBroadcast(for ipAddress: String) -> String? {
        let components = ipAddress.split(separator: ".").compactMap { Int($0) }
        guard components.count == 4,
              components.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
            return nil
        }
        
        // Para una máscara /24, el broadcast es X.X.X.255
        return "\(components[0]).\(components[1]).\(components[2]).255"
    }
    
    // MARK: - Cleanup
    
    deinit {
        print("[WoLService] Deinitializing WakeOnLANService")
        // Cleanup will happen automatically when the object is deallocated
    }
}
