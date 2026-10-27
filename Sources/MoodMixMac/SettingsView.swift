import MoodMixCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Spotify") {
                TextField("Client ID", text: $model.clientID)
                if !model.clientID.isEmpty && !model.clientIDLooksValid {
                    Label("That doesn't look like a Client ID (32 letters and digits). Make sure it isn't the Client secret.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if model.isLoggedIn {
                    HStack {
                        Text(model.canEditPlaylists ? "Connected, with permission to save playlists." : "Connected. Log in again to allow saving playlists and removing duplicates.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Log in again") { Task { await model.logIn(with: LoopbackAuthProvider()) } }
                    }
                }
                Text("Create an app at developer.spotify.com/dashboard, select Web API, and add the Redirect URI **http://127.0.0.1:8888/callback**. Then paste its Client ID here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcuts (work in any app)") {
                ForEach(HotKeys.shared.shortcuts) { shortcut in
                    HStack {
                        Text(shortcut.title)
                        Spacer()
                        Text(shortcut.keys).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
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
