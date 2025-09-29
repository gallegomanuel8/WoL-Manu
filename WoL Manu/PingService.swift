//
//  PingService.swift
//  WoL Manu
//
//  Created by Manuel Alonso Rodriguez on 28/9/25.
//

import Foundation
import SwiftUI
import Combine

enum DeviceStatus {
    case online
    case offline
    case unknown
    
    var color: Color {
        switch self {
        case .online:
            return .green
        case .offline:
            return .red
        case .unknown:
            return .gray
        }
    }
    
    var description: String {
        switch self {
        case .online:
            return "En línea"
        case .offline:
            return "Desconectado"
        case .unknown:
            return "Desconocido"
        }
    }
}

@MainActor
class PingService: ObservableObject {
    @Published var deviceStatus: DeviceStatus = .unknown
    
    private var timer: Timer?
    private var currentIPAddress: String = ""
    
    // MARK: - Timer Management
    
    /// Start monitoring device status with periodic ping
    /// - Parameter ipAddress: IP address to ping
    func startMonitoring(ipAddress: String) {
        stopMonitoring()
        
        guard !ipAddress.isEmpty else {
            deviceStatus = .unknown
            return
        }
        
        currentIPAddress = ipAddress
        deviceStatus = .unknown
        
        // Perform initial ping
        performPing()
        
        // Setup timer to ping every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performPing()
            }
        }
    }
    
    /// Stop monitoring device status
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        deviceStatus = .unknown
    }
    
    // MARK: - Ping Functionality
    
    /// Perform ping command to check device status
    private func performPing() {
        guard !currentIPAddress.isEmpty else {
            deviceStatus = .unknown
            return
        }
        
        Task {
            let isOnline = await executePingCommand(to: currentIPAddress)
            await MainActor.run {
                deviceStatus = isOnline ? .online : .offline
            }
        }
    }
    
    /// Execute ping command using Process
    /// - Parameter ipAddress: IP address to ping
    /// - Returns: True if ping was successful, false otherwise
    private func executePingCommand(to ipAddress: String) async -> Bool {
        print("[PingService] Attempting to ping: \(ipAddress)")
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            
            // Try different ping paths - sandboxed apps might need different locations
            let possiblePingPaths = ["/sbin/ping", "/usr/sbin/ping", "/bin/ping"]
            var pingPath: String?
            
            for path in possiblePingPaths {
                if FileManager.default.fileExists(atPath: path) {
                    pingPath = path
                    break
                }
            }
            
            guard let validPingPath = pingPath else {
                print("[PingService] Error: ping command not found in any of the expected paths")
                continuation.resume(returning: false)
                return
            }
            
            print("[PingService] Using ping at: \(validPingPath)")
            
            task.executableURL = URL(fileURLWithPath: validPingPath)
            task.arguments = ["-c", "1", "-W", "3000", ipAddress]  // 1 ping, 3 second timeout
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            
            do {
                print("[PingService] Executing command: \(validPingPath) \(task.arguments?.joined(separator: " ") ?? "")")
                try task.run()
                
                task.terminationHandler = { process in
                    let success = process.terminationStatus == 0
                    
                    // Read output for debugging
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        print("[PingService] Ping output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                    
                    if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                        print("[PingService] Ping error: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                    
                    print("[PingService] Ping result for \(ipAddress): \(success ? "SUCCESS" : "FAILED") (status: \(process.terminationStatus))")
                    continuation.resume(returning: success)
                }
                
            } catch {
                print("[PingService] Error executing ping command: \(error)")
                print("[PingService] Error details: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Manual Ping
    
    /// Perform a one-time ping to check device status
    /// - Parameter ipAddress: IP address to ping
    func performSinglePing(to ipAddress: String) async -> Bool {
        guard !ipAddress.isEmpty else { return false }
        
        let result = await executePingCommand(to: ipAddress)
        
        await MainActor.run {
            deviceStatus = result ? .online : .offline
        }
        
        return result
    }
    
    // MARK: - Update IP Address
    
    /// Update the IP address being monitored
    /// - Parameter newIPAddress: New IP address to monitor
    func updateIPAddress(_ newIPAddress: String) {
        if timer != nil {
            startMonitoring(ipAddress: newIPAddress)
        } else {
            currentIPAddress = newIPAddress
        }
    }
    
    deinit {
        print("[PingService] Deinitializing PingService")
        timer?.invalidate()
        timer = nil
    }
}