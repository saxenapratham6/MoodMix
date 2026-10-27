import AVFoundation
import MoodMixCore
import SwiftUI

@main
struct MoodMixApp: App {
    @State private var model: AppModel = {
        let model = AppModel()
        model.momentProvider = { MomentContext(headphones: Self.headphonesConnected) }
        model.preferredDeviceType = "Smartphone"
        model.beforePlayback = { [unowned model] in await SpotifyHandoff.shared.ensureDevice(for: model) }
        return model
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onOpenURL { url in Task { await handle(url) } }
        }
    }

    /// Widgets open `moodmix://generate?mood=chill` (or `mood=auto`).
    @MainActor
    private func handle(_ url: URL) async {
        guard url.scheme == "moodmix", url.host == "generate" else { return }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "mood" }?.value
        // A cold launch from a widget: give the saved library a moment to load.
        for _ in 0..<20 where model.tracks.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        model.journeyMode = false
        if let value, let mood = Mood(rawValue: value) {
            model.autoMood = false
            model.mood = mood
        } else {
            model.autoMood = true
        }
        await model.generate()
    }

    static var headphonesConnected: Bool {
        let headphonePorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { headphonePorts.contains($0.portType) }
    }
}
