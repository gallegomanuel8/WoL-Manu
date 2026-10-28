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
        WindowGroup {
            ContentView()
                .environmentObject(configManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Window("Analizador de red", id: "scanner") {
            NetworkScannerView()
                .environmentObject(configManager)
        }
        .defaultSize(width: 980, height: 560)
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenScannerCommand()
            }
        }
    }
}

private struct OpenScannerCommand: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button("Analizador de red") {
            openWindow(id: "scanner")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
