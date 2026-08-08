import AppKit
import SwiftUI

@main
struct MPCMidiConverterApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = ConverterViewModel.shared

    var body: some Scene {
        Window("MPC MIDI Converter", id: "converter") {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 480)
        }
        .defaultSize(width: 860, height: 500)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open MIDI Files…") {
                    model.chooseFiles()
                }
                .keyboardShortcut("o")

                Button("Create Profile from XPM…") {
                    model.chooseXPMProgram()
                }
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
