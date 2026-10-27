import AppKit

/// Makes sure the Spotify desktop app is running, so MoodMix always has a device to play on.
enum SpotifyLauncher {
    static let bundleID = "com.spotify.client"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Launches Spotify hidden in the background if it isn't open yet.
    @MainActor
    static func ensureRunning() async {
        guard !isRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        // Give it a moment to sign in and register as a Spotify Connect device.
        try? await Task.sleep(for: .seconds(3))
    }

    /// Asks the Spotify app itself to play a track over AppleScript. This works even when Spotify's
    /// remote-control (Connect) session is stuck. macOS asks once for permission to control Spotify.
    @MainActor
    static func playDirectly(_ uri: String) async -> Bool {
        await ensureRunning()
        let safeURI = uri.filter { $0.isLetter || $0.isNumber || $0 == ":" }
        let source = "tell application id \"\(bundleID)\" to play track \"\(safeURI)\""
        return await Task.detached {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            return error == nil
        }.value
    }

    @MainActor
    static func bringToFront() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.unhide()
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
