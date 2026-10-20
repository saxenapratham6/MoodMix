import MoodMixCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Spotify") {
                TextField("Client ID", text: $model.clientID)
                Text("Create an app at developer.spotify.com/dashboard, select Web API, and add the Redirect URI **http://127.0.0.1:8888/callback**. Then paste its Client ID here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude (mood labels)") {
                SecureField("Anthropic API key", text: $model.anthropicKey)
                TextField("Model", text: $model.claudeModel)
                Text("Each song is labeled once and cached. Use claude-haiku-5-5 here for a much cheaper first pass over a huge playlist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
