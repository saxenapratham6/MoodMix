import AppKit
import MoodMixCore
import SwiftUI

@MainActor
enum Shared {
    static let model: AppModel = {
        let model = AppModel()
        model.beforePlayback = { await SpotifyLauncher.ensureRunning() }
        model.momentProvider = { MomentContext(headphones: AudioRoute.headphonesConnected) }
        return model
    }()
    static let palette = ArtworkPalette()
    static var widget: WidgetController?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A widget, not a window: no Dock icon, just the floating widget and a menu bar item.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let widget = WidgetController(model: Shared.model)
            widget.show()
            Shared.widget = widget
            Task { await SpotifyLauncher.ensureRunning() }
            if ProcessInfo.processInfo.environment["MOODMIX_STRESS_RESIZE"] != nil { runStressTest(widget) }
        }
    }

    /// Development check: cycles every widget state quickly to catch layout crashes.
    @MainActor
    private func runStressTest(_ widget: WidgetController) {
        Task {
            try? await Task.sleep(for: .seconds(4))
            for i in 0..<48 {
                try? await Task.sleep(for: .milliseconds(350))
                switch i % 8 {
                case 0: widget.expand()
                case 2, 3: NotificationCenter.default.post(name: .moodMixTogglePlaylists, object: nil)
                case 4: widget.collapse()
                case 5: widget.shrinkToBubble()
                case 6: widget.setBubbleHover(true)
                case 7:
                    widget.setBubbleHover(false)
                    try? await Task.sleep(for: .milliseconds(600))
                    widget.restoreFromBubble()
                default: break
                }
                Shared.model.mood = Mood.allCases[i % Mood.allCases.count]
                Shared.model.buildMix()
            }
            widget.resetPosition()
            print("stress done")
        }
    }
}

@main
struct MoodMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("MoodMix", systemImage: "waveform") {
            MenuBarPanel()
                .environment(Shared.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(Shared.model)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
