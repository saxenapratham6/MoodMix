import MoodMixCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if !model.isLoggedIn {
                LoginView()
            } else if model.selectedPlaylist == nil {
                ContentUnavailableView("Pick a playlist", systemImage: "music.note.list",
                                       description: Text("MoodMix only plays songs from the playlist you choose."))
            } else {
                MixView()
            }
        }
        .toolbar {
            if let busy = model.busy {
                ToolbarItem {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("MoodMix").font(.largeTitle.bold())
            Text("Mood-based, smoothly ordered mixes from your own Spotify playlist.")
                .foregroundStyle(.secondary)
            if model.clientID.isEmpty {
                Button("Add Spotify Client ID…") { openSettings() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Log in with Spotify") {
                    Task { await model.logIn(with: LoopbackAuthProvider()) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.busy != nil)
            }
        }
        .padding(40)
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedPlaylistID) {
            Section("Your playlists") {
                ForEach(model.playlists) { playlist in
                    HStack {
                        Label(playlist.name, systemImage: "music.note.list")
                        Spacer()
                        Text("\(playlist.trackCount)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(playlist.id)
                }
            }
        }
        .onChange(of: model.selectedPlaylistID) { Task { await model.loadPlaylist() } }
        .safeAreaInset(edge: .bottom) {
            if model.isLoggedIn {
                Button("Log out") { Task { await model.logOut() } }
                    .buttonStyle(.borderless)
                    .padding()
            }
        }
    }
}

private struct MixView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            header
            moodPicker
            HStack(spacing: 24) {
                Picker("Energy", selection: $model.arc) {
                    ForEach(EnergyArc.allCases) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 260)
                Stepper("Length: \(model.minutes) min", value: $model.minutes, in: 15...360, step: 15)
                HStack {
                    Text("Favorites")
                    Slider(value: $model.favoriteWeight, in: 0...1)
                        .frame(width: 140)
                }
            }
            HStack {
                Button(model.mix.isEmpty ? "Build mix" : "Remix", systemImage: "wand.and.stars") { model.buildMix() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.tracks.isEmpty || model.busy != nil)
                Button("Play on Spotify", systemImage: "play.fill") { Task { await model.playMix() } }
                    .disabled(model.mix.isEmpty || model.busy != nil)
                Spacer()
                if !model.mix.isEmpty {
                    let minutes = model.mix.map(\.track.durationMs).reduce(0, +) / 60_000
                    Text("\(model.mix.count) songs · \(minutes) min").foregroundStyle(.secondary)
                }
            }
            MixTable(entries: model.mix)
            Text("For DJ-style blends, turn on **Crossfade** (6–8 s) or **Automix** in Spotify → Settings → Playback. MoodMix orders songs so neighbours share key and tempo, which makes those fades land smoothly.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .navigationTitle(model.selectedPlaylist?.name ?? "MoodMix")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.selectedPlaylist?.name ?? "").font(.title.bold())
                Text("\(model.tracks.count) songs · \(model.analyzedCount) analyzed · \(model.tracks.filter { model.favorites.score(for: $0.id) > 0 }.count) favorites")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.analyzedCount < model.tracks.count {
                Button("Analyze moods", systemImage: "sparkles") { Task { await model.analyze() } }
                    .disabled(model.busy != nil)
            }
        }
    }

    private var moodPicker: some View {
        @Bindable var model = model
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Mood.allCases) { mood in
                let selected = model.mood == mood
                Button {
                    model.mood = mood
                } label: {
                    Label(mood.title, systemImage: mood.symbol)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.green.opacity(0.25) : Color.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.green : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MixTable: View {
    let entries: [MixEntry]

    var body: some View {
        Table(entries) {
            TableColumn("#") { e in Text("\((entries.firstIndex(of: e) ?? 0) + 1)").monospacedDigit().foregroundStyle(.secondary) }
                .width(28)
            TableColumn("Title") { e in
                HStack(spacing: 4) {
                    if e.favoriteScore > 0 { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
                    Text(e.track.name)
                }
            }
            TableColumn("Artist") { e in Text(e.track.artistLine).foregroundStyle(.secondary) }
            TableColumn("BPM") { e in Text(e.profile?.features.map { "\(Int($0.tempo.rounded()))" } ?? "–").monospacedDigit() }
                .width(44)
            TableColumn("Key") { e in
                Text(e.profile?.features.flatMap { MixBuilder.camelot(key: $0.key, mode: $0.mode)?.description } ?? "–")
            }
            .width(40)
            TableColumn("Energy") { e in
                ProgressView(value: e.profile?.features?.energy ?? 0).tint(.orange)
            }
            .width(70)
            TableColumn("Blend") { e in
                if let t = e.transition {
                    Text(t.label)
                        .font(.caption)
                        .foregroundStyle(t.score >= 0.75 ? .green : t.score >= 0.5 ? .orange : .red)
                }
            }
            .width(56)
        }
    }
}
