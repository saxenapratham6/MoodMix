import AppKit
import MoodMixCore
import SwiftUI

/// The whole MoodMix UI: a slim bar at the bottom of the screen that springs open into a control card.
struct WidgetView: View {
    @Environment(AppModel.self) private var model
    let controller: WidgetController
    @State private var expanded = false
    @State private var showingPlaylists = false

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                ExpandedCard(showingPlaylists: $showingPlaylists)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            MiniBar(expanded: expanded, toggle: toggle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func toggle() {
        if expanded {
            withAnimation(.spring(duration: 0.3)) {
                expanded = false
                showingPlaylists = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { controller.resize(expanded: false) }
        } else {
            controller.resize(expanded: true)
            withAnimation(.spring(duration: 0.4, bounce: 0.25).delay(0.05)) { expanded = true }
        }
    }
}

/// Dark glass background shared by the bar and the card.
private struct Glass: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            .background(Color.black.opacity(0.55), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }
}

private extension View {
    func glass(radius: CGFloat = 18) -> some View { modifier(Glass(radius: radius)) }
}

// MARK: - Collapsed bar

private struct MiniBar: View {
    @Environment(AppModel.self) private var model
    let expanded: Bool
    let toggle: () -> Void
    @State private var spotifyOpen = SpotifyLauncher.isRunning
    private let spotifyCheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            nowPlaying
            Spacer(minLength: 8)
            if spotifyOpen {
                transport
            } else {
                Button {
                    SpotifyLauncher.bringToFront()
                } label: {
                    Label("Open Spotify", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(SpotifyLauncher.isInstalled ? "Spotify is closed" : "Spotify isn't installed")
            }
            Button {
                Task { await model.generate() }
            } label: {
                Label("Generate", systemImage: "sparkles")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.green, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!model.isLoggedIn || model.tracks.isEmpty || model.busy != nil)
            .help("Play a fresh \(model.mood.title.lowercased()) mix from \(model.selectedPlaylist?.name ?? "your playlist")")

            Button(action: toggle) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .background(Theme.chip, in: .circle)
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse" : "Moods, playlists and more")
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .glass(radius: 32)
        .onReceive(spotifyCheck) { _ in spotifyOpen = SpotifyLauncher.isRunning }
    }

    @ViewBuilder private var nowPlaying: some View {
        if let np = model.nowPlaying {
            HStack(spacing: 10) {
                Artwork(url: np.track.artworkURL, size: 42, radius: 21)
                    .rotationEffect(.degrees(0))
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.track.name).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        if let mood = model.profiles[np.track.id]?.moods.first { MoodTag(mood: mood) }
                        Text(np.track.artistLine).font(.caption).foregroundStyle(Theme.subtext).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MoodMix").font(.callout.weight(.bold))
                    Text(model.busy ?? model.analysisStatus ?? "\(model.mood.title) · \(model.selectedPlaylist?.name ?? "pick a playlist")")
                        .font(.caption).foregroundStyle(Theme.subtext).lineLimit(1)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button { Task { await model.skipPrevious() } } label: { Image(systemName: "backward.fill") }
            Button { Task { await model.togglePlayPause() } } label: {
                Image(systemName: model.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(.white, in: .circle)
            }
            Button { Task { await model.skipNext() } } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Theme.subtext)
        .disabled(model.nowPlaying == nil)
    }
}

// MARK: - Expanded card

private struct ExpandedCard: View {
    @Environment(AppModel.self) private var model
    @Binding var showingPlaylists: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.isLoggedIn {
                LoginSection()
            } else {
                playlistHeader
                if showingPlaylists {
                    PlaylistPicker { showingPlaylists = false }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Controls()
                        .transition(.opacity)
                }
            }
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.dismissError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(10)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 10))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            LinearGradient(colors: [model.mood.color.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                .clipShape(.rect(cornerRadius: 22))
                .animation(.easeInOut(duration: 0.4), value: model.mood)
        }
        .glass(radius: 22)
    }

    private var playlistHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.3)) { showingPlaylists.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Artwork(url: model.selectedPlaylist?.imageURL, size: 46, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PLAYLIST").font(.caption2.weight(.bold)).foregroundStyle(Theme.subtext)
                        HStack(spacing: 6) {
                            Text(model.selectedPlaylist?.name ?? "Choose a playlist").font(.title3.weight(.bold)).lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(showingPlaylists ? 180 : 0))
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer()
            SettingsLink { Image(systemName: "gearshape.fill").foregroundStyle(Theme.subtext) }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                .help("Settings")
        }
    }
}

private struct PlaylistPicker: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.playlists) { playlist in
                    let selected = playlist.id == model.selectedPlaylistID
                    Button {
                        model.selectedPlaylistID = playlist.id
                        withAnimation(.spring(duration: 0.3)) { done() }
                    } label: {
                        HStack(spacing: 12) {
                            Artwork(url: playlist.imageURL, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).foregroundStyle(selected ? Theme.green : .white).lineLimit(1)
                                Text("\(playlist.trackCount) songs").font(.caption).foregroundStyle(Theme.subtext)
                            }
                            Spacer()
                            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.green) }
                        }
                        .padding(6)
                        .background(selected ? Theme.hover : .clear, in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

private struct Controls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            status

            section("Mood")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    Pill(title: mood.title, symbol: mood.symbol, selected: model.mood == mood, compact: true) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.mood = mood }
                    }
                }
            }

            section("Energy")
            HStack(spacing: 8) {
                ForEach(EnergyArc.allCases) { arc in
                    Pill(title: arc.title, selected: model.arc == arc, compact: true) { model.arc = arc }
                }
            }

            HStack(spacing: 16) {
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
                    Image(systemName: "heart.fill").foregroundStyle(Theme.green)
                    Text("Favorites").font(.caption).foregroundStyle(Theme.subtext)
                    Slider(value: $model.favoriteWeight, in: 0...1).tint(Theme.green)
                }
                .help("How much your most-played and liked songs count")
            }

            HStack(spacing: 8) {
                Button { Task { await model.generate() } } label: {
                    Label("Generate", systemImage: "sparkles")
                        .font(.callout.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(.black)
                        .background(Theme.green, in: .capsule)
                }
                .disabled(model.tracks.isEmpty || model.busy != nil)

                actionButton("Match", symbol: "dot.radiowaves.left.and.right",
                             help: "Queue songs from this playlist that fit what's playing now") {
                    await model.matchCurrentSong()
                }
                .disabled(model.nowPlaying == nil || model.busy != nil)

                actionButton(model.needsAnalysis ? "Analyze" : "Analyzed", symbol: model.needsAnalysis ? "waveform.badge.magnifyingglass" : "checkmark",
                             help: "Label moods for songs that don't have one yet") {
                    await model.analyze()
                }
                .disabled(!model.needsAnalysis || model.analysisStatus != nil)
            }
            .buttonStyle(.plain)

            upNext
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if let s = model.busy ?? model.analysisStatus {
                ProgressView().controlSize(.mini)
                Text(s)
            } else {
                Text("\(model.tracks.count) songs · \(model.taggedCount) with moods · \(model.favoriteCount) favorites")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.subtext)
        .lineLimit(1)
    }

    @ViewBuilder private var upNext: some View {
        if !model.mix.isEmpty {
            HStack {
                section("Up next")
                Spacer()
                let minutes = model.mix.map(\.track.durationMs).reduce(0, +) / 60_000
                Text("\(model.mix.count) songs · \(minutes) min").font(.caption).foregroundStyle(Theme.subtext)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(model.mix.enumerated()), id: \.element.id) { i, entry in
                        UpNextRow(index: i, entry: entry)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        } else {
            Spacer(minLength: 0)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.subtext)
    }

    private func actionButton(_ title: String, symbol: String, help: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.chip, in: .capsule)
        }
        .help(help)
    }
}

private struct UpNextRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let entry: MixEntry
    @State private var hovering = false

    var body: some View {
        let isCurrent = model.nowPlaying?.track.id == entry.id
        HStack(spacing: 10) {
            Artwork(url: entry.track.artworkURL, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track.name).font(.callout).lineLimit(1).foregroundStyle(isCurrent ? Theme.green : .white)
                Text(entry.track.artistLine).font(.caption).lineLimit(1).foregroundStyle(Theme.subtext)
            }
            Spacer()
            if entry.favoriteScore > 0 { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.green) }
            if let f = entry.profile?.features {
                Text("\(Int(f.tempo.rounded())) bpm").font(.caption.monospacedDigit()).foregroundStyle(Theme.subtext)
            }
            if let blend = entry.transition {
                Circle()
                    .fill(blend.score >= 0.75 ? Theme.green : blend.score >= 0.5 ? .orange : .red)
                    .frame(width: 7, height: 7)
                    .help("\(blend.label) blend from the previous song")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(hovering ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { Task { await model.playMix(from: index) } }
    }
}

private struct LoginSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
            Text("MoodMix").font(.system(size: 32, weight: .black))
            Text("Mood-based, smoothly ordered mixes from your own Spotify playlists.")
                .font(.callout).foregroundStyle(Theme.subtext).multilineTextAlignment(.center)
            if model.clientID.isEmpty {
                SettingsLink {
                    Text("Add Spotify Client ID").bold().foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            } else {
                Button {
                    Task { await model.logIn(with: LoopbackAuthProvider()) }
                } label: {
                    Text(model.busy ?? "Log in with Spotify").bold().foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Theme.green, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(model.busy != nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
