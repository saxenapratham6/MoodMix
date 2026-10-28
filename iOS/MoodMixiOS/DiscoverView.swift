import Charts
import MoodMixCore
import SwiftUI

// MARK: - Discover

/// Swipe through songs similar to yours: right adds them, up plays them next, left skips.
struct DiscoverTab: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var results: [Track] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if !search.isEmpty {
                    SearchResults(results: results) { search = "" }
                } else {
                    pickers
                    CardStack()
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background { DeckBackdrop() }
            .navigationTitle("Discover")
            .searchable(text: $search, prompt: "Search Spotify for a song to start from")
            .task(id: search) {
                try? await Task.sleep(for: .milliseconds(350))  // wait for typing to pause
                results = await model.searchSpotify(search)
            }
            .task { if model.deck.isEmpty { await model.refillDeck() } }
            .onDisappear { Task { await model.stopPreview() } }
        }
    }

    private var hint: String {
        "Swipe right to add to \(model.discoverTarget.title) · up to play next · left to skip · tap the cover to listen"
    }

    private var pickers: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Menu {
                Button("Your favorites", systemImage: "heart.fill") { reseed(.favorites) }
                Button("Your queue", systemImage: "list.bullet") { reseed(.queue) }
                Menu("A mood") {
                    ForEach(Mood.allCases) { mood in
                        Button(mood.title, systemImage: mood.symbol) { reseed(.mood(mood)) }
                    }
                }
                if case .song(let track) = model.discoverSeed {
                    Button(track.name, systemImage: "music.note") {}
                }
            } label: {
                pickerLabel("Based on", model.discoverSeed.title, symbol: "sparkles")
            }
            Menu {
                Button("Your queue", systemImage: "list.bullet") { model.discoverTarget = .queue }
                if model.canEditPlaylists {
                    ForEach(model.playlists) { playlist in
                        Button(playlist.name, systemImage: "music.note.list") {
                            model.discoverTarget = .playlist(id: playlist.id, name: playlist.name)
                        }
                    }
                }
            } label: {
                pickerLabel("Adds to", model.discoverTarget.title, symbol: "plus.circle")
            }
        }
    }

    private func pickerLabel(_ caption: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 0) {
                Text(caption.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white.opacity(0.55))
                Text(value).font(.footnote.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .liquidGlass(interactive: true, in: Capsule())
    }

    private func reseed(_ seed: DiscoverSeed) {
        model.discoverSeed = seed
        Task { await model.refillDeck(reset: true) }
    }
}

/// Search results: start the deck from a song, or keep it straight away.
private struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let results: [Track]
    let done: () -> Void

    var body: some View {
        List(results) { track in
            HStack(spacing: 12) {
                Artwork(url: track.artworkURL, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
                Button {
                    model.discoverSeed = .song(track)
                    done()
                    Task { await model.refillDeck(reset: true) }
                } label: {
                    Label("Similar", systemImage: "sparkles").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.green)
            }
            .listRowBackground(Color.white.opacity(0.05))
            .swipeActions(edge: .leading) {
                Button("Next") { model.playNext(track) }.tint(Theme.green)
            }
            .swipeActions(edge: .trailing) {
                Button("Add") { model.addToQueueEnd(track) }.tint(.blue)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if results.isEmpty { ContentUnavailableView.search }
        }
    }
}

/// The deck's background takes the top card's cover, blurred, like Spotify's Now Playing.
private struct DeckBackdrop: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black
            if let url = model.deck.first?.track.artworkURL {
                Artwork(url: url, size: 600, radius: 0)
                    .blur(radius: 70)
                    .opacity(0.55)
                    .id(url)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: model.deck.first?.id)
    }
}

private struct CardStack: View {
    @Environment(AppModel.self) private var model
    @State private var swipes = 0

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if model.deck.isEmpty {
                    VStack(spacing: 12) {
                        if model.loadingDeck {
                            ProgressView().controlSize(.large)
                            Text("Finding songs like yours…").font(.callout).foregroundStyle(.white.opacity(0.7))
                        } else {
                            Image(systemName: "rectangle.stack").font(.system(size: 44)).foregroundStyle(.white.opacity(0.5))
                            Text("No more songs right now").font(.headline)
                            Button("Find more") { Task { await model.refillDeck() } }.tint(Theme.green)
                        }
                    }
                    .frame(height: 440)
                } else {
                    ForEach(Array(model.deck.prefix(3).enumerated().reversed()), id: \.element.id) { index, card in
                        SwipeCard(card: card, isTop: index == 0) { action in
                            swipes += 1
                            Task { await model.swipe(card, action) }
                        }
                        .scaleEffect(1 - CGFloat(index) * 0.05)
                        .offset(y: CGFloat(index) * 14)
                        .opacity(index == 2 ? 0.6 : 1)
                        .allowsHitTesting(index == 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.deck.first?.id)
                    }
                }
            }
            .frame(height: 460)
            .sensoryFeedback(.impact(weight: .medium), trigger: swipes)

            if let top = model.deck.first {
                actionButtons(top)
            }
        }
    }

    private func actionButtons(_ card: DiscoveryCard) -> some View {
        HStack(spacing: 22) {
            roundButton("xmark", tint: .red, size: 54) { swipe(card, .skip) }
            roundButton(model.previewingID == card.id ? "pause.fill" : "play.fill", tint: .white, size: 46) {
                Task { await model.togglePreview(card) }
            }
            roundButton("text.line.first.and.arrowtriangle.forward", tint: .blue, size: 46) { swipe(card, .next) }
            roundButton("heart.fill", tint: Theme.green, size: 54) { swipe(card, .add) }
        }
    }

    private func swipe(_ card: DiscoveryCard, _ action: SwipeAction) {
        swipes += 1
        Task { await model.swipe(card, action) }
    }

    private func roundButton(_ symbol: String, tint: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .liquidGlass(interactive: true, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// One song card. Drag it: right adds, up plays next, left skips.
private struct SwipeCard: View {
    @Environment(AppModel.self) private var model
    let card: DiscoveryCard
    let isTop: Bool
    let onSwipe: (SwipeAction) -> Void
    @State private var drag: CGSize = .zero
    @State private var flying: SwipeAction?

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: card.track.artworkURL, size: 320, radius: 0)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(.rect)
                    .onTapGesture { Task { await model.togglePreview(card) } }
                if model.previewingID == card.id {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption.weight(.bold))
                        .symbolEffect(.variableColor.iterative)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(12)
                }
                stamps
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(card.track.name).font(.title3.weight(.bold)).lineLimit(1)
                Text(card.track.artistLine).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                HStack(spacing: 6) {
                    if let mood = card.mood { MoodTag(mood: mood) }
                    if let f = card.features {
                        Text("\(Int(f.tempo.rounded())) bpm").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                    if let popularity = card.popularity {
                        Label("\(popularity)", systemImage: "flame.fill").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Text(card.reason).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            .padding(16)
        }
        .frame(height: 440, alignment: .top)
        .background(Color(white: 0.09))
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 18)), anchor: .bottom)
        .gesture(isTop ? dragGesture : nil)
    }

    /// "ADD" / "NEXT" / "SKIP" stamps that fade in as you drag.
    private var stamps: some View {
        ZStack {
            stamp("ADD", color: Theme.green, visible: drag.width / threshold).frame(maxWidth: .infinity, alignment: .topLeading)
            stamp("SKIP", color: .red, visible: -drag.width / threshold).frame(maxWidth: .infinity, alignment: .topTrailing)
            stamp("NEXT", color: .blue, visible: -drag.height / threshold).frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func stamp(_ text: String, color: Color, visible: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(text == "ADD" ? -12 : text == "SKIP" ? 12 : 0))
            .opacity(Double(min(max(visible, 0), 1)))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let t = value.translation
                let action: SwipeAction? =
                    t.width > threshold ? .add :
                    t.width < -threshold ? .skip :
                    t.height < -threshold ? .next : nil
                guard let action else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                    return
                }
                // Fling it off screen, then tell the deck.
                withAnimation(.easeOut(duration: 0.25)) {
                    drag = action == .next ? CGSize(width: t.width, height: -900)
                        : CGSize(width: t.width > 0 ? 600 : -600, height: t.height)
                } completion: {
                    onSwipe(action)
                }
            }
    }
}

// MARK: - Profile

/// Who you are on Spotify and what you've discovered.
struct ProfileTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.discoverStats
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        avatar
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.profileName ?? "You").font(.title2.weight(.bold))
                            Text("\(model.tracks.count) songs in \(model.selectedPlaylist?.name ?? "your playlist")")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section("Discovery") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statTile("\(stats.explored)", "explored", symbol: "rectangle.stack.fill", tint: .white)
                        statTile("\(stats.added)", "added", symbol: "heart.fill", tint: Theme.green)
                        statTile("\(stats.queued)", "played next", symbol: "text.line.first.and.arrowtriangle.forward", tint: .blue)
                        statTile("\(stats.skipped)", "skipped", symbol: "xmark", tint: .red)
                        statTile("\(Int((stats.keepRate * 100).rounded()))%", "kept", symbol: "checkmark.seal.fill", tint: .yellow)
                        statTile("\(stats.streak())", "day streak", symbol: "flame.fill", tint: .orange)
                    }
                    .padding(.vertical, 6)
                }

                if !stats.keptMoods.isEmpty {
                    Section("Moods you discover") {
                        let moods = Mood.allCases.compactMap { mood in stats.keptMoods[mood.rawValue].map { (mood: mood, count: $0) } }
                        Chart(moods, id: \.mood) { item in
                            BarMark(x: .value("Songs", item.count), y: .value("Mood", item.mood.title))
                                .foregroundStyle(item.mood.color.gradient)
                                .cornerRadius(4)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(moods.count) * 28 + 10)
                    }
                }

                Section("Recent finds") {
                    if stats.recentFinds.isEmpty {
                        Text("Songs you keep in Discover show up here.").font(.footnote).foregroundStyle(.white.opacity(0.6))
                    }
                    ForEach(stats.recentFinds) { track in
                        SongRow(track: track)
                            .swipeActions(edge: .leading) {
                                Button("Next") { model.playNext(track) }.tint(Theme.green)
                            }
                    }
                }

                Section("Your library") {
                    LabeledContent("Songs with moods", value: "\(model.taggedCount)")
                    LabeledContent("Favorites", value: "\(model.favoriteCount)")
                    LabeledContent("Playlists", value: "\(model.playlists.count)")
                }
            }
            .scrollContentBackground(.hidden)
            .background { ArtBackdrop() }
            .navigationTitle("Profile")
            .task { await model.loadProfile() }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let url = model.profileImageURL {
            Artwork(url: url, size: 64, radius: 32)
        } else {
            Text(String((model.profileName ?? "M").prefix(1)).uppercased())
                .font(.title.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Theme.green, in: .circle)
        }
    }

    private func statTile(_ value: String, _ label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}
