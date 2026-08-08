import AppKit
import SwiftUI

@main
struct MPCMidiConverterApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = ConverterViewModel.shared

    var body: some Scene {
        Window("MPC MIDI Converter", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Apri file MIDI…") {
                    model.chooseFiles()
                }
                .keyboardShortcut("o")
            }
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        ConverterViewModel.shared.addFiles(urls)
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
