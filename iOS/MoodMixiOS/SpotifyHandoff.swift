import MoodMixCore
import UIKit

/// iOS can't start Spotify in the background. When there's nowhere to play, MoodMix opens Spotify,
/// waits for you to come back (via "◀ MoodMix" in the top-left corner), and then starts the mix.
@MainActor @Observable
final class SpotifyHandoff {
    static let shared = SpotifyHandoff()
    private(set) var waiting = false

    func ensureDevice(for model: AppModel) async {
        guard await !model.hasPlaybackDevice(),
              let spotify = URL(string: "spotify:"), UIApplication.shared.canOpenURL(spotify) else { return }
        waiting = true
        defer { waiting = false }
        guard await UIApplication.shared.open(spotify) else { return }
        // Wait for MoodMix to leave the screen, then to come back (up to two minutes).
        for _ in 0..<20 where UIApplication.shared.applicationState == .active {
            try? await Task.sleep(for: .milliseconds(150))
        }
        for _ in 0..<240 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(500))
        }
        // Spotify registers this phone as a device a moment after opening; the play request waits for it.
    }
}
