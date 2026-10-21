import AppKit
import MoodMixCore
import SwiftUI

/// The floating widget: a glass bar that grows a card out of itself, or shrinks into a bubble on a screen edge.
struct WidgetView: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    @Namespace private var glass
    @State private var showingPlaylists = false

    var body: some View {
        let accent = Shared.palette.accent ?? model.mood.color
        GlassGroup(spacing: 24) {
            if controller.mode == .bubble {
                Bubble(accent: accent)
                    .glassID("bubble", in: glass)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                VStack(spacing: WidgetController.gap) {
                    if controller.cardBelow {
                        bar(accent)
                        card(accent)
                    } else {
                        card(accent)
                        bar(accent)
                    }
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(WidgetController.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: controller.mode == .bubble ? .center : controller.cardBelow ? .top : .bottom)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task(id: model.nowPlaying?.track.artworkURL) {
            await Shared.palette.update(for: model.nowPlaying?.track.artworkURL)
        }
        .onChange(of: controller.showCard) { if !controller.showCard { showingPlaylists = false } }
        .onReceive(NotificationCenter.default.publisher(for: .moodMixTogglePlaylists)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showingPlaylists.toggle() }
        }
    }

    private func bar(_ accent: Color) -> some View {
        MiniBar(accent: accent)
            .glassID("bar", in: glass)
    }

    @ViewBuilder private func card(_ accent: Color) -> some View {
        if controller.showCard {
            let anchor: UnitPoint = controller.cardBelow ? .top : .bottom
            ExpandedCard(accent: accent, showingPlaylists: $showingPlaylists)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controller.cardHeightChanged($0) }
                .glassID("card", in: glass)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.35, anchor: anchor)
                        .combined(with: .opacity)
                        .combined(with: .offset(y: controller.cardBelow ? -24 : 24)),
                    removal: .scale(scale: 0.5, anchor: anchor).combined(with: .opacity)))
        }
    }
}

extension Notification.Name {
    static let moodMixTogglePlaylists = Notification.Name("MoodMixTogglePlaylists")
}

// MARK: - Bar

private struct MiniBar: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    let accent: Color
    @State private var spotifyOpen = SpotifyLauncher.isRunning
    private let spotifyCheck = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            NowPlayingLabel()
                .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 4)
            if spotifyOpen {
                Transport(size: .regular)
            } else {
                Button { SpotifyLauncher.bringToFront() } label: {
                    Label("Open Spotify", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.pressable)
            }
            GenerateButton(compact: true)
            CircleIconButton(symbol: "circle.dashed", help: "Shrink to a bubble (or drag the bar to a screen edge)") {
                controller.shrinkToBubble()
            }
            CircleIconButton(symbol: controller.cardBelow ? "chevron.down" : "chevron.up",
                             help: controller.showCard ? "Collapse" : "Moods, playlists and more",
                             rotation: controller.showCard ? 180 : 0) {
                controller.toggleExpanded()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(width: WidgetController.barSize.width, height: WidgetController.barSize.height)
        .background { DragHandle(onDragEnded: controller.dragEnded) }
        .overlay(alignment: .bottom) { ProgressLine().padding(.horizontal, 30).padding(.bottom, 4) }
        .background(alignment: .leading) {
            // A wash of the album color across the left of the bar, like Spotify's player.
            LinearGradient(colors: [accent.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .clipShape(Capsule())
                .allowsHitTesting(false)
        }
        .liquidGlass(tint: Color.black.opacity(0.35), in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onReceive(spotifyCheck) { _ in spotifyOpen = SpotifyLauncher.isRunning }
    }
}

struct NowPlayingLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if let np = model.nowPlaying {
                Artwork(url: np.track.artworkURL, size: 44, radius: 8)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .id(np.track.id)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.track.name).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        if let mood = model.profiles[np.track.id]?.moods.first { MoodTag(mood: mood) }
                        Text(np.track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Theme.green, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("MoodMix").font(.callout.weight(.bold))
                    Text(model.statusLine ?? "\(model.mood.title) · \(model.selectedPlaylist?.name ?? "pick a playlist")")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.nowPlaying?.track.id)
    }
}

private struct ProgressLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let np = model.nowPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                GeometryReader { geo in
                    let fraction = CGFloat(np.progress(at: context.date)) / CGFloat(max(np.track.durationMs, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(Theme.green).frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 2.5)
            }
            .allowsHitTesting(false)
        }
    }
}

struct Transport: View {
    enum Size { case regular, large }
    @Environment(AppModel.self) private var model
    var size: Size = .regular

    var body: some View {
        let big = size == .large
        HStack(spacing: big ? 22 : 14) {
            Button { Task { await model.skipPrevious() } } label: { Image(systemName: "backward.fill") }
            Button { Task { await model.togglePlayPause() } } label: {
                Image(systemName: model.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: big ? 17 : 14))
                    .foregroundStyle(.black)
                    .frame(width: big ? 40 : 32, height: big ? 40 : 32)
                    .background(.white, in: .circle)
            }
            Button { Task { await model.skipNext() } } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.pressable)
        .font(.system(size: big ? 16 : 13))
        .foregroundStyle(.white.opacity(0.85))
        .disabled(model.nowPlaying == nil)
    }
}

struct GenerateButton: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        Button { Task { await model.generate() } } label: {
            Label("Generate", systemImage: "sparkles")
                .font((compact ? Font.callout : .body).weight(.bold))
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 14 : 18)
                .padding(.vertical, compact ? 8 : 11)
                .foregroundStyle(.black)
                .background(Theme.green.gradient, in: .capsule)
                .shadow(color: Theme.green.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.pressable)
        .disabled(!model.isLoggedIn || model.tracks.isEmpty || model.busy != nil)
        .help("Play a fresh \(model.mood.title.lowercased()) mix from \(model.selectedPlaylist?.name ?? "your playlist")")
    }
}

private struct CircleIconButton: View {
    let symbol: String
    let help: String
    var rotation: Double = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .rotationEffect(.degrees(rotation))
                .frame(width: 30, height: 30)
                .liquidGlass(interactive: true, in: Circle())
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .help(help)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: rotation)
    }
}

// MARK: - Bubble

private struct Bubble: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    let accent: Color

    var body: some View {
        let d = WidgetController.bubbleDiameter
        ZStack {
            if let np = model.nowPlaying {
                Artwork(url: np.track.artworkURL, size: d - 14, radius: (d - 14) / 2)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let fraction = CGFloat(np.progress(at: context.date)) / CGFloat(max(np.track.durationMs, 1))
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d - 6, height: d - 6)
                }
                if !np.isPlaying {
                    Image(systemName: "pause.fill").font(.system(size: 14, weight: .bold))
                        .padding(6).background(.black.opacity(0.5), in: .circle)
                }
            } else {
                Image(systemName: "waveform").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.green)
            }
        }
        .frame(width: d, height: d)
        .liquidGlass(tint: accent.opacity(0.4), in: Circle())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .overlay { DragHandle(onClick: controller.restoreFromBubble, onDragEnded: controller.dragEnded) }
        .help("Click to open · drag away from the edge to move")
    }
}

// MARK: - Card

private struct ExpandedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    let accent: Color
    @Binding var showingPlaylists: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.isLoggedIn {
                LoginSection()
            } else {
                header
                if showingPlaylists {
                    PlaylistPicker { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showingPlaylists = false } }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Controls()
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.dismissError() } label: { Image(systemName: "xmark") }.buttonStyle(.pressable)
                }
                .padding(10)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 12))
            }
        }
        .padding(18)
        .frame(width: WidgetController.barSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .background { DragHandle(onDragEnded: controller.dragEnded) }
        .background(alignment: .top) {
            LinearGradient(colors: [accent.opacity(0.7), accent.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .allowsHitTesting(false)
        }
        .liquidGlass(tint: Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showingPlaylists.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Artwork(url: model.selectedPlaylist?.imageURL, size: 52, radius: 8)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PLAYLIST").font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.65))
                        HStack(spacing: 6) {
                            Text(model.selectedPlaylist?.name ?? "Choose a playlist").font(.title3.weight(.heavy)).lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(showingPlaylists ? 180 : 0))
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            Spacer()
            CircleIconButton(symbol: "circle.dashed", help: "Shrink to a bubble") { controller.shrinkToBubble() }
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .liquidGlass(interactive: true, in: Circle())
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .help("Settings")
        }
    }
}

private struct PlaylistPicker: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void

    var body: some View {
        let rowHeight: CGFloat = 56
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.playlists) { playlist in
                    let selected = playlist.id == model.selectedPlaylistID
                    Button {
                        model.selectedPlaylistID = playlist.id
                        done()
                    } label: {
                        HStack(spacing: 12) {
                            Artwork(url: playlist.imageURL, size: 44, radius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).font(.callout.weight(.semibold))
                                    .foregroundStyle(selected ? Theme.green : .white).lineLimit(1)
                                Text("Playlist · \(playlist.trackCount) songs").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                        }
                        .padding(6)
                        .frame(height: rowHeight - 4)
                        .background(selected ? Color.white.opacity(0.1) : .clear, in: .rect(cornerRadius: 10))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: CGFloat(min(max(model.playlists.count, 1), 6)) * rowHeight)
    }
}

private struct Controls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            status

            GlassGroup(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    section("Mood")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Mood.allCases) { mood in
                            GlassPill(title: mood.title, symbol: mood.symbol, selected: model.mood == mood, fill: true) {
                                withAnimation(.easeInOut(duration: 0.25)) { model.mood = mood }
                            }
                        }
                    }
                    section("Energy").padding(.top, 6)
                    HStack(spacing: 8) {
                        ForEach(EnergyArc.allCases) { arc in
                            GlassPill(title: arc.title, selected: model.arc == arc, fill: true) { model.arc = arc }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
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
                    Text("Favorites").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Slider(value: $model.favoriteWeight, in: 0...1).tint(Theme.green)
                }
                .help("How much your most-played and liked songs count")
            }

            HStack(spacing: 8) {
                GenerateButton()
                actionButton("Match", symbol: "dot.radiowaves.left.and.right",
                             help: "Queue songs from this playlist that fit what's playing now") {
                    await model.matchCurrentSong()
                }
                .disabled(model.nowPlaying == nil || model.busy != nil)
                actionButton(model.needsAnalysis ? "Analyze" : "Analyzed",
                             symbol: model.needsAnalysis ? "waveform.badge.magnifyingglass" : "checkmark",
                             help: "Label moods for songs that don't have one yet") {
                    await model.analyze()
                }
                .disabled(!model.needsAnalysis || model.analysisStatus != nil)
            }

            if !model.mix.isEmpty { upNext.transition(.opacity.combined(with: .move(edge: .bottom))) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.mix.isEmpty)
    }

    private var status: some View {
        HStack(spacing: 8) {
            if let s = model.statusLine {
                if model.rateLimitedUntil != nil {
                    Image(systemName: "hourglass").foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(s)
            } else {
                Text("\(model.tracks.count) songs · \(model.taggedCount) with moods · \(model.favoriteCount) favorites")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }

    private var upNext: some View {
        let rowHeight: CGFloat = 46
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                section("Up next")
                Spacer()
                let minutes = model.mix.map(\.track.durationMs).reduce(0, +) / 60_000
                Text("\(model.mix.count) songs · \(minutes) min").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.mix.enumerated()), id: \.element.id) { i, entry in
                        UpNextRow(index: i, entry: entry).frame(height: rowHeight - 2)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: CGFloat(min(model.mix.count, 5)) * rowHeight)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
    }

    private func actionButton(_ title: String, symbol: String, help: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .liquidGlass(interactive: true, in: Capsule())
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
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
            ZStack {
                Artwork(url: entry.track.artworkURL, size: 36, radius: 6)
                if hovering {
                    Image(systemName: "play.fill").font(.caption).padding(6).background(.black.opacity(0.55), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track.name).font(.callout.weight(.medium)).lineLimit(1).foregroundStyle(isCurrent ? Theme.green : .white)
                Text(entry.track.artistLine).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if entry.favoriteScore > 0 { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.green) }
            if let f = entry.profile?.features {
                Text("\(Int(f.tempo.rounded())) bpm").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            }
            if let blend = entry.transition {
                Circle()
                    .fill(blend.score >= 0.75 ? Theme.green : blend.score >= 0.5 ? .orange : .red)
                    .frame(width: 7, height: 7)
                    .help("\(blend.label) blend from the previous song")
            }
        }
        .padding(.horizontal, 6)
        .background(hovering ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { Task { await model.playMix(from: index) } }
        .help("Play from here")
    }
}

private struct LoginSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
            Text("MoodMix").font(.system(size: 32, weight: .black))
            Text("Mood-based, smoothly ordered mixes from your own Spotify playlists.")
                .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if model.clientID.isEmpty {
                SettingsLink {
                    Text("Add Spotify Client ID").bold().foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            } else {
                Button {
                    Task { await model.logIn(with: LoopbackAuthProvider()) }
                } label: {
                    Text(model.busy ?? "Log in with Spotify").bold().foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Theme.green, in: .capsule)
                }
                .buttonStyle(.pressable)
                .disabled(model.busy != nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
