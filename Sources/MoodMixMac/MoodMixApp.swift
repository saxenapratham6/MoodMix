import AppKit
import MoodMixCore
import SwiftUI

@MainActor
enum Shared {
    static let model: AppModel = {
        let model = AppModel()
        model.beforePlayback = { await SpotifyLauncher.ensureRunning() }
        return model
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var widget: WidgetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A widget, not a window: no Dock icon, just the floating bar and a menu bar item.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let widget = WidgetController(model: Shared.model)
            widget.show()
            self.widget = widget
            Task { await SpotifyLauncher.ensureRunning() }
        }
    }
}

@main
struct MoodMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("MoodMix", systemImage: "waveform") {
            Button("Show / Hide Widget") { delegate.widget?.toggleVisible() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Open Spotify") { SpotifyLauncher.bringToFront() }
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Button("Quit MoodMix") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView()
                .environment(Shared.model)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
