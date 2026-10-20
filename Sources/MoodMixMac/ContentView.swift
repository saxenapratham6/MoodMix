import MoodMixCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Sidebar()
                    .frame(width: 290)
                Group {
                    if !model.isLoggedIn {
                        LoginView()
                    } else if model.selectedPlaylist == nil {
                        EmptyPanel()
                    } else {
                        PlaylistPanel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panel)
                .clipShape(.rect(cornerRadius: 8))
            }
            .padding([.horizontal, .top], 8)
            NowPlayingBar()
                .frame(height: 80)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill")
                Text("Your Library").font(.headline)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help("Settings")
            }
            .foregroundStyle(Theme.subtext)
            .padding(.horizontal, 18)
            .padding(.top, 34)   // clear the window buttons
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.playlists) { PlaylistRow(playlist: $0) }
                }
                .padding(.horizontal, 8)
            }

            if model.isLoggedIn {
                Button("Log out") { Task { await model.logOut() } }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Theme.subtext)
                    .padding(18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct PlaylistRow: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedPlaylistID == playlist.id
        Button {
            model.selectedPlaylistID = playlist.id
        } label: {
            HStack(spacing: 12) {
                Artwork(url: playlist.imageURL, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .foregroundStyle(selected ? Theme.green : .white)
                        .lineLimit(1)
                    Text("Playlist · \(playlist.trackCount) songs")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(selected ? Theme.hover : hovering ? Theme.elevated : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Panels

private struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 72)).foregroundStyle(Theme.green)
            Text("MoodMix").font(.system(size: 44, weight: .black))
            Text("Mood-based, smoothly ordered mixes from your own Spotify playlists.")
                .foregroundStyle(Theme.subtext)
            if model.clientID.isEmpty {
                SettingsLink { Text("Add Spotify Client ID").bold().foregroundStyle(.black).padding(.horizontal, 28).padding(.vertical, 12).background(.white, in: .capsule) }
                    .buttonStyle(.plain)
            } else {
                Button {
                    Task { await model.logIn(with: LoopbackAuthProvider()) }
                } label: {
                    Text(model.busy ?? "Log in with Spotify").bold().foregroundStyle(.black)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Theme.green, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(model.busy != nil)
            }
        }
        .padding(40)
    }
}

private struct EmptyPanel: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 48)).foregroundStyle(Theme.subtext)
            Text("Pick a playlist").font(.title.bold())
            Text("MoodMix only plays songs from the playlist you choose.").foregroundStyle(Theme.subtext)
        }
    }
}

private enum Tab: Hashable { case mix, songs }

private struct PlaylistPanel: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .songs
    @State private var filterByMood = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                controls
                tabBar
                TrackListHeader(showBlend: tab == .mix)
                LazyVStack(spacing: 0) {
                    switch tab {
                    case .mix:
                        ForEach(Array(model.mix.enumerated()), id: \.element.id) { i, entry in
                            TrackRow(index: i, track: entry.track, blend: entry.transition) {
                                Task { await model.playMix(from: i) }
                            }
                        }
                        if model.mix.isEmpty { emptyMix }
                    case .songs:
                        let songs = visibleSongs
                        ForEach(Array(songs.enumerated()), id: \.element.id) { i, track in
                            TrackRow(index: i, track: track, blend: nil) {
                                Task { await model.play(Array(songs[i...].prefix(100))) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                Text("Tip: turn on Crossfade (6–8 s) or Automix in Spotify → Settings → Playback. MoodMix orders each mix so neighbouring songs share key and tempo, which makes those fades land smoothly.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .padding(24)
            }
        }
        .scrollIndicators(.never)
    }

    private var visibleSongs: [Track] {
        guard filterByMood else { return model.tracks }
        return model.tracks.filter { model.profiles[$0.id]?.moods.contains(model.mood) ?? false }
    }

    private var header: some View {
        let playlist = model.selectedPlaylist!
        return HStack(alignment: .bottom, spacing: 24) {
            Artwork(url: playlist.imageURL, size: 210, radius: 6)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            VStack(alignment: .leading, spacing: 8) {
                Text("Playlist").font(.callout.weight(.semibold))
                Text(playlist.name)
                    .font(.system(size: 64, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("\(model.tracks.count) songs · \(model.taggedCount) mood-tagged · \(model.favoriteCount) favorites")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                if let status = model.analysisStatus ?? model.busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(status)
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                } else if model.needsAnalysis && !model.tracks.isEmpty {
                    Button("Label \(model.tracks.count - model.taggedCount) remaining songs") { Task { await model.analyze() } }
                        .buttonStyle(.plain)
                        .font(.callout.bold())
                        .foregroundStyle(Theme.green)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [model.mood.color.opacity(0.85), model.mood.color.opacity(0.35), Theme.panel],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.easeInOut(duration: 0.4), value: model.mood)
    }

    private var controls: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 22) {
                Button {
                    tab = .mix
                    Task { await model.playMix() }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Theme.green, in: .circle)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .help("Play a \(model.mood.title.lowercased()) mix")
                .disabled(model.tracks.isEmpty)

                Button {
                    model.buildMix()
                    tab = .mix
                } label: {
                    Image(systemName: "shuffle").font(.system(size: 22)).foregroundStyle(Theme.subtext)
                }
                .buttonStyle(.plain)
                .help("New mix")

                Menu {
                    Picker("Energy", selection: $model.arc) {
                        ForEach(EnergyArc.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(model.arc.title, systemImage: "chart.line.uptrend.xyaxis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Picker("Length", selection: $model.minutes) {
                        ForEach([30, 45, 60, 90, 120, 180, 240], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("\(model.minutes) min", systemImage: "clock")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.subtext)
                    Slider(value: $model.favoriteWeight, in: 0...1).frame(width: 120).tint(Theme.green)
                }
                .help("How much your favorites count")
                Spacer()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Mood.allCases) { mood in
                        Pill(title: mood.title, symbol: mood.symbol, selected: model.mood == mood) {
                            model.mood = mood
                            if tab == .mix { model.buildMix() }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            Pill(title: "All songs", selected: tab == .songs) { tab = .songs }
            Pill(title: model.mix.isEmpty ? "Your mix" : "Your mix · \(model.mix.count)", selected: tab == .mix) {
                if model.mix.isEmpty { model.buildMix() }
                tab = .mix
            }
            Spacer()
            if tab == .songs {
                Toggle("Only \(model.mood.title.lowercased())", isOn: $filterByMood)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.green)
            } else if !model.mix.isEmpty {
                let minutes = model.mix.map(\.track.durationMs).reduce(0, +) / 60_000
                Text("\(model.mix.count) songs · about \(minutes) min").foregroundStyle(Theme.subtext)
            }
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var emptyMix: some View {
        VStack(spacing: 8) {
            Text("Press play to get a \(model.mood.title.lowercased()) mix").font(.title3.bold())
            Text("Only songs from this playlist, ordered to blend smoothly.").foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Track list

private struct TrackListHeader: View {
    let showBlend: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("#").frame(width: 28, alignment: .trailing)
                Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                Text("Album").frame(maxWidth: .infinity, alignment: .leading)
                Text("Mood").frame(width: 170, alignment: .leading)
                Text(showBlend ? "Blend" : "BPM · Key").frame(width: 90, alignment: .leading)
                Image(systemName: "clock").frame(width: 48, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(Theme.subtext)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider().overlay(Theme.hover)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let track: Track
    let blend: MoodMixCore.Transition?
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        let profile = model.profiles[track.id]
        let isCurrent = model.nowPlaying?.track.id == track.id
        HStack(spacing: 16) {
            ZStack {
                if hovering {
                    Image(systemName: "play.fill").font(.caption)
                } else if isCurrent && model.nowPlaying?.isPlaying == true {
                    Image(systemName: "waveform").foregroundStyle(Theme.green).symbolEffect(.variableColor.iterative)
                } else {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(isCurrent ? Theme.green : Theme.subtext)
                }
            }
            .frame(width: 28, alignment: .trailing)

            HStack(spacing: 12) {
                Artwork(url: track.artworkURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(track.name).lineLimit(1).foregroundStyle(isCurrent ? Theme.green : .white)
                        if model.favorites.score(for: track.id) > 0 {
                            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.green)
                        }
                    }
                    Text(track.artistLine).font(.callout).lineLimit(1).foregroundStyle(Theme.subtext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.album).font(.callout).lineLimit(1).foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let moods = profile?.moods, !moods.isEmpty {
                    ForEach(moods.prefix(2), id: \.self) { MoodTag(mood: $0) }
                } else {
                    Text("Labeling…").font(.caption).foregroundStyle(Theme.subtext.opacity(0.6))
                }
            }
            .frame(width: 170, alignment: .leading)

            Group {
                if let blend {
                    Text(blend.label)
                        .foregroundStyle(blend.score >= 0.75 ? Theme.green : blend.score >= 0.5 ? .orange : .red)
                } else if let f = profile?.features {
                    let key = MixBuilder.camelot(key: f.key, mode: f.mode)?.description ?? "–"
                    Text("\(Int(f.tempo.rounded())) · \(key)").foregroundStyle(Theme.subtext)
                } else {
                    Text("–").foregroundStyle(Theme.subtext)
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 90, alignment: .leading)

            Text(formatTime(track.durationMs)).font(.callout.monospacedDigit()).foregroundStyle(Theme.subtext)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(hovering ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .overlay(alignment: .leading) {
            if hovering {
                Button(action: play) { Color.clear.frame(width: 44) }.buttonStyle(.plain).padding(.leading, 8)
            }
        }
    }
}

// MARK: - Now playing

private struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if let np = model.nowPlaying {
                HStack(spacing: 12) {
                    Artwork(url: np.track.artworkURL, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(np.track.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(np.track.artistLine).font(.caption).foregroundStyle(Theme.subtext).lineLimit(1)
                    }
                }
                .frame(width: 320, alignment: .leading)

                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 28) {
                        controlButton("backward.end.fill") { await model.skipPrevious() }
                        Button {
                            Task { await model.togglePlayPause() }
                        } label: {
                            Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.black)
                                .frame(width: 34, height: 34)
                                .background(.white, in: .circle)
                        }
                        .buttonStyle(.plain)
                        controlButton("forward.end.fill") { await model.skipNext() }
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let progress = np.progress(at: context.date)
                        HStack(spacing: 8) {
                            Text(formatTime(progress)).frame(width: 40, alignment: .trailing)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.hover)
                                    Capsule().fill(.white)
                                        .frame(width: geo.size.width * CGFloat(progress) / CGFloat(max(np.track.durationMs, 1)))
                                }
                            }
                            .frame(height: 4)
                            Text(formatTime(np.track.durationMs)).frame(width: 40, alignment: .leading)
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.subtext)
                    }
                    .frame(width: 520)
                }
                Spacer()

                HStack(spacing: 6) {
                    ForEach(model.profiles[np.track.id]?.moods ?? [], id: \.self) { MoodTag(mood: $0) }
                }
                .frame(width: 320, alignment: .trailing)
            } else {
                Text(model.isLoggedIn ? "Nothing playing. Open Spotify on any device, then press play here." : "")
                    .font(.callout)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    private func controlButton(_ symbol: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.subtext)
        }
        .buttonStyle(.plain)
    }
}
