import AppKit
import Charts
import MoodMixCore
import SwiftUI
import UniformTypeIdentifiers

/// The floating widget: a glass bar that grows a card out of itself, or shrinks into a bubble on a screen edge.
struct WidgetView: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    @Namespace private var glass
    @State private var showingPlaylists = false

    var body: some View {
        let accent = Shared.palette.accent ?? model.mood.color
        GlassGroup(spacing: 0) {
            if controller.mode == .bubble {
                bubbleWithPill(accent)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                VStack(spacing: WidgetController.gap) {
                    if controller.cardBelow {
                        bar(accent)
                        cardSlot(accent)
                    } else {
                        cardSlot(accent)
                        bar(accent)
                    }
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(WidgetController.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: rootAlignment)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task(id: model.nowPlaying?.track.artworkURL) {
            await Shared.palette.update(for: model.nowPlaying?.track.artworkURL)
        }
        .onChange(of: controller.showCard) {
            if controller.showCard { model.refreshIfStale() } else { showingPlaylists = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moodMixTogglePlaylists)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showingPlaylists.toggle() }
        }
    }

    private var rootAlignment: Alignment {
        switch controller.mode {
        case .bubble: controller.bubbleSide == .right ? .trailing : .leading
        default: controller.cardBelow ? .top : .bottom
        }
    }

    private func bar(_ accent: Color) -> some View {
        MiniBar(accent: accent)
    }

    /// The card lives in a slot clipped at the bar's edge, so it slides out from behind the bar
    /// (up when the widget is low on screen, down when it's near the top), like macOS's Now Playing panel.
    @ViewBuilder private func cardSlot(_ accent: Color) -> some View {
        if controller.mode == .expanded {
            let below = controller.cardBelow
            ZStack(alignment: below ? .top : .bottom) {
                if controller.showCard {
                    ExpandedCard(accent: accent, showingPlaylists: $showingPlaylists)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controller.cardHeightChanged($0) }
                        .transition(.move(edge: below ? .top : .bottom).combined(with: .opacity))
                }
            }
            .frame(width: WidgetController.barSize.width, height: controller.cardHeight, alignment: below ? .top : .bottom)
            .mask(alignment: below ? .top : .bottom) {
                Rectangle()
                    .padding(.horizontal, -WidgetController.pad)
                    .padding(below ? .bottom : .top, -WidgetController.pad)
            }
        }
    }

    private func bubbleWithPill(_ accent: Color) -> some View {
        let right = controller.bubbleSide == .right
        return HStack(spacing: WidgetController.pillGap) {
            if right { pill(right: right) }
            Bubble(accent: accent)
            if !right { pill(right: right) }
        }
        .background { HoverTracker { controller.setBubbleHover($0) } }
    }

    @ViewBuilder private func pill(right: Bool) -> some View {
        if controller.pillVisible {
            BubblePill()
                .transition(.move(edge: right ? .trailing : .leading)
                    .combined(with: .scale(scale: 0.5, anchor: right ? .trailing : .leading))
                    .combined(with: .opacity))
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
    var onTap: () -> Void = {}

    var body: some View {
        Button {
            onTap()
            Task { await model.generate() }
        } label: {
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
        let np = model.nowPlaying
        ZStack {
            VinylRecord(artworkURL: np?.track.artworkURL, spinning: np?.isPlaying == true, size: d - 8)
            if let np {
                // Song progress around the record.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let fraction = CGFloat(np.progress(at: context.date)) / CGFloat(max(np.track.durationMs, 1))
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d - 3, height: d - 3)
                }
                if !np.isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(.black.opacity(0.7), in: .circle)
                        .offset(x: d * 0.3, y: d * 0.3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(width: d, height: d)
        .liquidGlass(tint: accent.opacity(0.35), in: Circle())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: np?.isPlaying)
        .overlay { DragHandle(onClick: controller.restoreFromBubble, onDragEnded: controller.dragEnded) }
        .help("Click to open · drag away from the edge to move")
    }
}

/// Slides out of the bubble on hover so you can control playback without opening the bar.
private struct BubblePill: View {
    @Environment(WidgetController.self) private var controller

    var body: some View {
        HStack(spacing: 10) {
            Transport(size: .regular)
            Button { controller.restoreFromBubble() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .liquidGlass(interactive: true, in: Circle())
            }
            .buttonStyle(.pressable)
            .help("Open the bar")
        }
        .padding(.horizontal, 12)
        .frame(width: WidgetController.pillWidth, height: 52)
        .liquidGlass(tint: Color.black.opacity(0.35), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}

// MARK: - Card

private enum CardTab { case mix, queue, insights }

private struct ExpandedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(WidgetController.self) private var controller
    let accent: Color
    @Binding var showingPlaylists: Bool
    @State private var tab: CardTab = .mix

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
                    tabBar
                    Group {
                        switch tab {
                        case .mix:
                            Controls { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { tab = .queue } }
                        case .queue:
                            QueueView()
                        case .insights:
                            InsightsView()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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

    private var tabBar: some View {
        HStack(spacing: 8) {
            GlassPill(title: "Mix", symbol: "slider.horizontal.3", selected: tab == .mix) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = .mix }
            }
            GlassPill(title: model.queue.isEmpty ? "Queue" : "Queue · \(model.queue.upcoming.count)",
                      symbol: "list.bullet", selected: tab == .queue) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = .queue }
            }
            GlassPill(title: "Insights", symbol: "chart.bar.xaxis", selected: tab == .insights) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = .insights }
            }
            Spacer()
        }
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
            SleepTimerMenu()
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
    /// Called when a mix starts, to show the queue.
    var onStarted: () -> Void = {}

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            status

            GlassGroup(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        section(model.journeyMode ? "Journey" : "Mood")
                        Spacer()
                        SmallToggle(title: "Auto", symbol: "sparkles", on: model.autoMood && !model.journeyMode) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                model.autoMood.toggle()
                                if model.autoMood { model.journeyMode = false }
                            }
                        }
                        .help("Pick the mood from the time of day, your headphones and your habits")
                        SmallToggle(title: "Journey", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                    on: model.journeyMode) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                model.journeyMode.toggle()
                                if model.journeyMode { model.autoMood = false }
                            }
                        }
                        .help("Travel through several moods in one mix, e.g. Sad → Chill → Happy")
                    }
                    if model.journeyMode {
                        journeyRoute
                    } else if model.autoMood, let suggestion = model.suggestion {
                        Label("\(suggestion.mood.title) · \(suggestion.reason)", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.white.opacity(0.75))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Mood.allCases) { mood in
                            GlassPill(title: mood.title, symbol: mood.symbol, selected: isSelected(mood), fill: true) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if model.journeyMode {
                                        model.toggleJourneyMood(mood)
                                    } else {
                                        model.autoMood = false
                                        model.mood = mood
                                    }
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if model.journeyMode, let step = model.journey.firstIndex(of: mood) {
                                    Text("\(step + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black)
                                        .frame(width: 16, height: 16)
                                        .background(Theme.green, in: .circle)
                                        .offset(x: 4, y: -5)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                    if !model.journeyMode {
                        section("Energy").padding(.top, 6)
                        HStack(spacing: 8) {
                            ForEach(EnergyArc.allCases) { arc in
                                GlassPill(title: arc.title, selected: model.arc == arc, fill: true) { model.arc = arc }
                            }
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
                GenerateButton(onTap: onStarted)
                actionButton("Match", symbol: "dot.radiowaves.left.and.right",
                             help: "Queue songs from this playlist that fit what's playing now") {
                    onStarted()
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
        }
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
                if let sleep = model.sleepTimerText {
                    Label(sleep, systemImage: "moon.zzz.fill").foregroundStyle(Theme.green)
                }
                if model.skippedCount > 0 {
                    Text("· \(model.skippedCount) duplicate\(model.skippedCount == 1 ? "" : "s") skipped")
                        .help("Your Spotify playlist has \(model.selectedPlaylist?.trackCount ?? 0) entries; songs added more than once are counted once.")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
    }

    private func isSelected(_ mood: Mood) -> Bool {
        if model.journeyMode { return model.journey.contains(mood) }
        if model.autoMood { return model.suggestion?.mood == mood }
        return model.mood == mood
    }

    @ViewBuilder private var journeyRoute: some View {
        if model.journey.isEmpty {
            Text("Tap up to 4 moods in the order you want to go through them.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        } else {
            HStack(spacing: 6) {
                ForEach(Array(model.journey.enumerated()), id: \.element) { i, mood in
                    if i > 0 { Image(systemName: "arrow.right").font(.caption2.bold()).foregroundStyle(.white.opacity(0.5)) }
                    MoodTag(mood: mood)
                }
                Spacer()
                if model.journey.count < 2 {
                    Text("add one more").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Button("Clear") { withAnimation { model.clearJourney() } }
                    .buttonStyle(.pressable).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
        }
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

private struct QueueView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var dragging: UUID?
    @State private var dropTarget: UUID?

    var body: some View {
        let rowHeight: CGFloat = 46
        VStack(alignment: .leading, spacing: 12) {
            if model.queue.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing queued yet").font(.callout.weight(.semibold))
                    Text("Press Generate for a mood mix, or add songs below.").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 6)
            } else {
                if !model.queueActive {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                        Text("Spotify is playing something else.").font(.caption)
                        Spacer()
                        Button("Resume queue") { Task { await model.resumeQueue() } }
                            .buttonStyle(.pressable)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.green)
                    }
                    .padding(10)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 12))
                }
                if let current = model.queue.current {
                    section("Now playing")
                    QueueRow(item: current, isCurrent: true).frame(height: rowHeight - 2)
                }
                HStack {
                    section("Next up")
                    Spacer()
                    SaveQueueButton()
                    if let mood = model.queue.mood {
                        Label("then more \(mood.title.lowercased())", systemImage: "infinity")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                            .help("When the queue runs low, MoodMix adds more \(mood.title.lowercased()) songs from this playlist.")
                    }
                }
                let visibleRows = min(max(model.queue.upcoming.count, 1), 7)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.queue.upcoming) { item in
                            QueueRow(item: item, isCurrent: false)
                                .frame(height: rowHeight - 2)
                                .overlay(alignment: .top) {
                                    if dropTarget == item.id {
                                        Capsule().fill(Theme.green).frame(height: 2).offset(y: -2)
                                    }
                                }
                                .onDrag {
                                    dragging = item.id
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: QueueDrop(target: item.id, model: model, dragging: $dragging, dropTarget: $dropTarget))
                        }
                        // Drop here to move a song to the very end.
                        Color.clear
                            .frame(height: 14)
                            .overlay(alignment: .top) {
                                if dropTarget == QueueDrop.endID { Capsule().fill(Theme.green).frame(height: 2) }
                            }
                            .onDrop(of: [.text], delegate: QueueDrop(target: QueueDrop.endID, model: model, dragging: $dragging, dropTarget: $dropTarget))
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
                .frame(height: CGFloat(visibleRows) * rowHeight + 18)
                .mask {
                    // Soft edges hint that there's more to scroll.
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                           .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.queue.upcoming.map(\.id))
            }
            AddSongField(search: $search)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
    }
}

/// Drag a queued song onto another to put it in that spot (a green line shows where it lands).
private struct QueueDrop: DropDelegate {
    static let endID = UUID()
    let target: UUID
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var dropTarget: UUID?

    func dropEntered(info: DropInfo) { dropTarget = target }
    func dropExited(info: DropInfo) { if dropTarget == target { dropTarget = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            dropTarget = nil
        }
        let upcoming = model.queue.upcoming
        guard let dragging, dragging != target, let from = upcoming.firstIndex(where: { $0.id == dragging }) else { return false }
        let to = target == Self.endID ? upcoming.count : upcoming.firstIndex(where: { $0.id == target })
        guard let to else { return false }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            model.moveInQueue(fromOffsets: IndexSet(integer: from), toOffset: to)
        }
        return true
    }
}

private struct QueueRow: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Artwork(url: item.track.artworkURL, size: 36, radius: 6)
                if isCurrent && model.nowPlaying?.isPlaying == true {
                    Image(systemName: "waveform").font(.caption.bold()).foregroundStyle(Theme.green)
                        .symbolEffect(.variableColor.iterative)
                        .padding(5).background(.black.opacity(0.55), in: .circle)
                } else if hovering && !isCurrent {
                    Image(systemName: "play.fill").font(.caption).padding(6).background(.black.opacity(0.55), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.track.name).font(.callout.weight(.medium)).lineLimit(1)
                    .foregroundStyle(isCurrent ? Theme.green : .white)
                Text(item.track.artistLine).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if item.addedByYou {
                Image(systemName: "person.fill").font(.caption2).foregroundStyle(.white.opacity(0.6)).help("Added by you")
            }
            if let mood = model.profiles[item.track.id]?.moods.first { MoodTag(mood: mood) }
            if hovering && !isCurrent {
                Button { model.removeFromQueue(item.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.pressable)
                .help("Remove from queue")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(hovering ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !isCurrent { Task { await model.jumpInQueue(to: item.id) } } }
        .contextMenu { RetagMenu(trackID: item.track.id) }
    }
}

/// Saves the queue as a private playlist in Spotify, then offers to open it.
private struct SaveQueueButton: View {
    @Environment(AppModel.self) private var model
    @State private var saved: URL?

    var body: some View {
        if let saved {
            Button { NSWorkspace.shared.open(saved) } label: {
                Label("Saved · Open", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
            }
            .buttonStyle(.pressable)
        } else if model.canEditPlaylists {
            Button {
                Task { saved = await model.saveQueueAsPlaylist() }
            } label: {
                Label("Save as playlist", systemImage: "square.and.arrow.down").font(.caption.weight(.semibold))
            }
            .buttonStyle(.pressable)
            .disabled(model.busy != nil)
            .help("Save this queue as a private playlist in your Spotify library")
        } else {
            Button { Task { await model.logIn(with: LoopbackAuthProvider()) } } label: {
                Label("Allow saving", systemImage: "lock.open").font(.caption.weight(.semibold))
            }
            .buttonStyle(.pressable)
            .help("Log in to Spotify once more so MoodMix may create playlists")
        }
    }
}

/// How the playlist breaks down by mood, your most-played songs, and housekeeping.
private struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemove = false

    var body: some View {
        let counts = Mood.allCases.map { mood in
            (mood: mood, count: model.tracks.filter { model.profiles[$0.id]?.moods.first == mood }.count)
        }
        let thin = counts.filter { $0.count < 25 }.sorted { $0.count < $1.count }
        let learned = model.tracks.filter { !(model.profiles[$0.id]?.feedback?.isEmpty ?? true) }.count
        let mostYou = model.tracks.sorted { model.favorites.score(for: $0.id) > model.favorites.score(for: $1.id) }.prefix(5)

        VStack(alignment: .leading, spacing: 12) {
            section("Your playlist by mood")
            Chart(counts, id: \.mood) { item in
                BarMark(x: .value("Songs", item.count), y: .value("Mood", item.mood.title))
                    .foregroundStyle(item.mood.color.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(.white.opacity(0.85)) }
            }
            .frame(height: 170)

            if let thinnest = thin.first {
                Label("Only \(thinnest.count) \(thinnest.mood.title.lowercased()) songs. Add a few more for longer \(thinnest.mood.title.lowercased()) mixes.",
                      systemImage: "lightbulb")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if learned > 0 {
                Label("Learned from how you listened to \(learned) songs (skips and full plays).", systemImage: "brain")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }

            section("Most you").padding(.top, 4)
            VStack(spacing: 4) {
                ForEach(Array(mostYou)) { track in
                    HStack(spacing: 10) {
                        Artwork(url: track.artworkURL, size: 30, radius: 5)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(track.name).font(.callout).lineLimit(1)
                            Text(track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        if let mood = model.profiles[track.id]?.moods.first { MoodTag(mood: mood) }
                    }
                    .contextMenu { RetagMenu(trackID: track.id) }
                }
            }

            section("Duplicates").padding(.top, 4)
            duplicates

            section("Move to another service").padding(.top, 4)
            HStack(spacing: 8) {
                exportButton("Export this playlist", all: false)
                exportButton("Export all", all: true)
            }
            Text("Saves a CSV that TuneMyMusic or Soundiiz can import into Apple Music or YouTube Music, plus a JSON with each song's moods, tempo and key.")
                .font(.caption).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportButton(_ title: String, all: Bool) -> some View {
        Button { Task { await Exporter.export(all: all, model: model) } } label: {
            Label(title, systemImage: "square.and.arrow.up").font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .liquidGlass(interactive: true, in: Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(model.busy != nil)
    }

    @ViewBuilder private var duplicates: some View {
        if !model.canEditPlaylists {
            HStack {
                Text("Log in again to let MoodMix tidy your playlist.").font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Log in") { Task { await model.logIn(with: LoopbackAuthProvider()) } }
                    .buttonStyle(.pressable).font(.caption.weight(.bold)).foregroundStyle(Theme.green)
            }
        } else if let found = model.duplicates {
            if found.isEmpty {
                Label("No duplicates in this playlist.", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.green)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(found) { dup in
                        Text("• \(dup.name) — \(dup.artists) (×\(dup.copies))").font(.caption).lineLimit(1)
                    }
                }
                if confirmRemove {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This edits \(model.selectedPlaylist?.name ?? "the playlist") in Spotify: the extra copies are removed and one copy stays where the first one was. Spotify will show it as re-added today.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Cancel") { confirmRemove = false }.buttonStyle(.pressable).font(.caption.weight(.semibold))
                            Spacer()
                            Button("Remove \(found.count) extra cop\(found.count == 1 ? "y" : "ies")") {
                                confirmRemove = false
                                Task { await model.removeDuplicates() }
                            }
                            .buttonStyle(.pressable)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
                } else {
                    Button("Remove extra copies…") { confirmRemove = true }
                        .buttonStyle(.pressable).font(.caption.weight(.bold)).foregroundStyle(Theme.green)
                }
            }
        } else {
            Button("Check for duplicates") { Task { await model.findDuplicates() } }
                .buttonStyle(.pressable).font(.caption.weight(.bold)).foregroundStyle(Theme.green)
                .disabled(model.busy != nil)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
    }
}

/// Right-click a song: "This song is more…" — your call beats Claude's label.
struct RetagMenu: View {
    @Environment(AppModel.self) private var model
    let trackID: String

    var body: some View {
        let current = model.profiles[trackID]?.moods.first
        Menu("This song is more…") {
            ForEach(Mood.allCases) { mood in
                Button {
                    model.retag(trackID, as: mood)
                } label: {
                    Label(mood.title + (mood == current ? " ✓" : ""), systemImage: mood.symbol)
                }
            }
        }
    }
}

struct SleepTimerMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("Off") { model.setSleepTimer(.off) }
            Divider()
            Button("At the end of this song") { model.setSleepTimer(.endOfSong) }
                .disabled(model.nowPlaying == nil)
            Button("At the end of the mix") { model.setSleepTimer(.endOfMix) }
                .disabled(model.queue.isEmpty)
            Divider()
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("In \(minutes) minutes (fade out)") { model.setSleepTimer(.minutes(minutes)) }
            }
        } label: {
            Image(systemName: model.sleepTimer.isOn ? "moon.zzz.fill" : "moon.zzz")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.sleepTimer.isOn ? Theme.green : .white)
                .frame(width: 30, height: 30)
                .liquidGlass(interactive: true, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.sleepTimerText ?? "Sleep timer")
    }
}

/// A small on/off capsule (Auto, Journey).
struct SmallToggle: View {
    let title: String
    let symbol: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(on ? .black : .white)
                .background(on ? Theme.green : .clear, in: .capsule)
                .modifier(OffGlass(on: on))
        }
        .buttonStyle(.pressable)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: on)
    }

    private struct OffGlass: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            if on { content } else { content.liquidGlass(interactive: true, in: Capsule()) }
        }
    }
}

/// Search the playlist and drop any song into the queue; the queue's mood continues after it.
private struct AddSongField: View {
    @Environment(AppModel.self) private var model
    @Binding var search: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                TextField("Add a song from \(model.selectedPlaylist?.name ?? "your playlist")…", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) }
                        .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlass(in: Capsule())

            if !search.isEmpty {
                let results = model.searchPlaylist(search, limit: 6)
                if results.isEmpty {
                    Text("No songs in this playlist match.").font(.caption).foregroundStyle(.white.opacity(0.6)).padding(.leading, 12)
                }
                ForEach(results) { track in
                    HStack(spacing: 10) {
                        Artwork(url: track.artworkURL, size: 32, radius: 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.name).font(.callout).lineLimit(1)
                            Text(track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        if let mood = model.profiles[track.id]?.moods.first { MoodTag(mood: mood) }
                        Button {
                            model.playNext(track)
                            search = ""
                        } label: {
                            Label("Next", systemImage: "text.line.first.and.arrowtriangle.forward").font(.caption.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .liquidGlass(interactive: true, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .help("Play right after the current song")
                        Button {
                            model.addToQueueEnd(track)
                            search = ""
                        } label: {
                            Image(systemName: "plus").font(.caption.weight(.bold))
                                .frame(width: 26, height: 26)
                                .liquidGlass(interactive: true, in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .help("Add to the end of the queue")
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 40)
                }
            }
        }
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
