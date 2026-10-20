import AppKit
import MoodMixCore
import SwiftUI

@main
struct MoodMixApp: App {
    @State private var model = AppModel()

    init() {
        // Built with SwiftPM rather than an .app bundle, so ask for a normal Dock app explicitly.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("MoodMix") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
