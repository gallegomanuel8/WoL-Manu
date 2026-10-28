//
//  WoL_ManuApp.swift
//  WoL Manu
//
//  Created by WoL Manu on 28/9/25.
//

import SwiftUI

@main
struct WoL_ManuApp: App {
    @StateObject private var configManager = ConfigurationManager()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(configManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenWindowCommands()
            }
        }
        
        Window("Analizador de red", id: "scanner") {
            NetworkScannerView()
                .environmentObject(configManager)
        }
        .defaultSize(width: 1180, height: 600)
        
        WindowGroup("Herramientas de red", id: "tools", for: String.self) { $target in
            NetworkToolsView(initialTarget: target)
                .environmentObject(configManager)
        }
        .defaultSize(width: 860, height: 560)
        
        MenuBarExtra("WoL Manu", systemImage: "power") {
            MenuBarView()
                .environmentObject(configManager)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct OpenWindowCommands: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button("Analizador de red") {
            openWindow(id: "scanner")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        
        Button("Herramientas de red") {
            openWindow(id: "tools")
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
