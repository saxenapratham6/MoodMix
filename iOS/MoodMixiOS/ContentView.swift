import Charts
import MoodMixCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        Group {
            if model.isLoggedIn {
                TabView {
                    Tab("Now", systemImage: "waveform") { NowView(showSettings: $showSettings) }
                    Tab("Queue", systemImage: "list.bullet") { QueueTab() }
                    Tab("Insights", systemImage: "chart.bar.xaxis") { InsightsTab() }
                }
                .tint(Theme.green)
            } else {
                LoginView(showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .overlay(alignment: .top) {
            if SpotifyHandoff.shared.waiting {
                Label("Opening Spotify… come back with ◀ MoodMix (top left) and your mix starts.", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(tint: Theme.green.opacity(0.3), in: Capsule())
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: SpotifyHandoff.shared.waiting)
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.dismissError() }
            if model.errorMessage?.contains("Open Spotify") == true {
                Button("Open Spotify") { UIApplication.shared.open(URL(string: "spotify:")!) }
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Background

/// Spotify-style backdrop: the album cover blown up and blurred, fading to black.
private struct ArtBackdrop: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black
            if let url = model.nowPlaying?.track.artworkURL {
                Artwork(url: url, size: 600, radius: 0)
                    .blur(radius: 60)
                    .opacity(0.65)
                    .transition(.opacity)
                    .id(url)
            }
            LinearGradient(colors: [model.mood.color.opacity(0.35), .black.opacity(0.4), .black],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: model.nowPlaying?.track.id)
    }
}

// MARK: - Now

private struct NowView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    nowPlaying
                    MoodPicker()
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.never)
            .background { ArtBackdrop() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { PlaylistMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .refreshable { await model.refreshLibrary() }
        }
    }

    @ViewBuilder private var nowPlaying: some View {
        VStack(spacing: 16) {
            if let np = model.nowPlaying {
                VinylRecord(artworkURL: np.track.artworkURL, spinning: np.isPlaying, size: 300)
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.4), value: np.track.id)
                VStack(spacing: 4) {
                    Text(np.track.name).font(.title2.weight(.bold)).lineLimit(1)
                    Text(np.track.artistLine).font(.callout).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    HStack(spacing: 5) {
                        ForEach(model.profiles[np.track.id]?.moods.prefix(2) ?? [], id: \.self) { MoodTag(mood: $0) }
                    }
                    .padding(.top, 2)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let progress = np.progress(at: context.date)
                    VStack(spacing: 4) {
                        ProgressView(value: Double(progress), total: Double(max(np.track.durationMs, 1)))
                            .tint(.white)
                        HStack {
                            Text(formatTime(progress))
                            Spacer()
                            Text("-" + formatTime(np.track.durationMs - progress))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                transport
            } else {
                VStack(spacing: 10) {
                    VinylRecord(artworkURL: nil, spinning: false, size: 220)
                        .padding(.bottom, 8)
                    Text("Nothing playing").font(.title3.bold())
                    Text("Pick a mood and press Generate. Keep Spotify open on this phone or another device.")
                        .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button("Open Spotify") { UIApplication.shared.open(URL(string: "spotify:")!) }
                        .font(.callout.weight(.semibold)).tint(Theme.green)
                }
                .padding(.vertical, 40)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { Task { await model.skipPrevious() } } label: { Image(systemName: "backward.fill").font(.title2) }
            Button { Task { await model.togglePlayPause() } } label: {
                Image(systemName: model.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title)
                    .foregroundStyle(.black)
                    .frame(width: 68, height: 68)
                    .background(.white, in: .circle)
            }
            Button { Task { await model.skipNext() } } label: { Image(systemName: "forward.fill").font(.title2) }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: model.nowPlaying?.isPlaying)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await model.generate() }
            } label: {
                Label(model.statusLine ?? "Generate", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.black)
                    .background(Theme.green.gradient, in: .capsule)
            }
            .disabled(model.tracks.isEmpty || model.busy != nil)
            .sensoryFeedback(.success, trigger: model.queue.current?.id)

            Button { Task { await model.matchCurrentSong() } } label: {
                Label("Match this song", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .liquidGlass(interactive: true, in: Capsule())
            }
            .disabled(model.nowPlaying == nil || model.busy != nil)

            Text("\(model.tracks.count) songs · \(model.taggedCount) with moods · \(model.favoriteCount) favorites")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

private struct PlaylistMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.playlists) { playlist in
                Button {
                    model.selectedPlaylistID = playlist.id
                } label: {
                    Label("\(playlist.name) · \(playlist.trackCount)",
                          systemImage: playlist.id == model.selectedPlaylistID ? "checkmark" : "music.note.list")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Artwork(url: model.selectedPlaylist?.imageURL, size: 26, radius: 4)
                Text(model.selectedPlaylist?.name ?? "Choose a playlist").font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
        }
    }
}

private struct MoodPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.journeyMode ? "JOURNEY" : "MOOD").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Toggle(isOn: $model.autoMood) { Label("Auto", systemImage: "sparkles") }
                    .toggleStyle(.button).font(.caption.weight(.semibold)).tint(Theme.green)
                    .onChange(of: model.autoMood) { if model.autoMood { model.journeyMode = false } }
                Toggle(isOn: $model.journeyMode) { Label("Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    .toggleStyle(.button).font(.caption.weight(.semibold)).tint(Theme.green)
                    .onChange(of: model.journeyMode) { if model.journeyMode { model.autoMood = false } }
            }
            if model.autoMood && !model.journeyMode, let suggestion = model.suggestion {
                Label("\(suggestion.mood.title) · \(suggestion.reason)", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if model.journeyMode {
                Text(model.journey.isEmpty ? "Tap up to 4 moods in order." : model.journey.map(\.title).joined(separator: " → "))
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    let selected = model.journeyMode ? model.journey.contains(mood)
                        : model.autoMood ? model.suggestion?.mood == mood : model.mood == mood
                    Button {
                        withAnimation(.snappy) {
                            if model.journeyMode {
                                model.toggleJourneyMood(mood)
                            } else {
                                model.autoMood = false
                                model.mood = mood
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mood.symbol).font(.system(size: 17, weight: .semibold))
                            Text(mood.title).font(.caption2.weight(.semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selected ? .black : .white)
                        .background(selected ? Color.white : .clear, in: .rect(cornerRadius: 14))
                        .modifier(TileGlass(selected: selected))
                        .overlay(alignment: .topTrailing) {
                            if model.journeyMode, let step = model.journey.firstIndex(of: mood) {
                                Text("\(step + 1)").font(.caption2.bold()).foregroundStyle(.black)
                                    .frame(width: 16, height: 16).background(Theme.green, in: .circle).offset(x: 4, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
        }
    }

    private struct TileGlass: ViewModifier {
        let selected: Bool
        func body(content: Content) -> some View {
            if selected { content } else { content.liquidGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14)) }
        }
    }
}

// MARK: - Queue

private struct QueueTab: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var savedURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if !search.isEmpty {
                    Section("Add from \(model.selectedPlaylist?.name ?? "playlist")") {
                        ForEach(model.searchPlaylist(search, limit: 20)) { track in
                            SongRow(track: track)
                                .swipeActions(edge: .leading) {
                                    Button("Next") { model.playNext(track); search = "" }.tint(Theme.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Add") { model.addToQueueEnd(track); search = "" }.tint(.blue)
                                }
                                .contextMenu {
                                    Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { model.playNext(track); search = "" }
                                    Button("Add to end", systemImage: "text.append") { model.addToQueueEnd(track); search = "" }
                                }
                        }
                    }
                } else if model.queue.isEmpty {
                    ContentUnavailableView("Nothing queued", systemImage: "list.bullet",
                                           description: Text("Generate a mix, or search to add songs."))
                        .listRowBackground(Color.clear)
                } else {
                    if !model.queueActive {
                        Button("Spotify is playing something else · Resume queue") { Task { await model.resumeQueue() } }
                            .font(.callout.weight(.semibold)).foregroundStyle(Theme.green)
                    }
                    if let current = model.queue.current {
                        Section("Now playing") { SongRow(track: current.track, highlight: true) }
                    }
                    Section {
                        ForEach(model.queue.upcoming) { item in
                            SongRow(track: item.track, addedByYou: item.addedByYou)
                                .contentShape(.rect)
                                .onTapGesture(count: 2) { Task { await model.jumpInQueue(to: item.id) } }
                                .contextMenu { RetagMenu(trackID: item.track.id) }
                        }
                        .onMove { model.moveInQueue(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in offsets.map { model.queue.upcoming[$0].id }.forEach(model.removeFromQueue) }
                    } header: {
                        HStack {
                            Text("Next up")
                            Spacer()
                            if let mood = model.queue.mood { Text("then more \(mood.title.lowercased())").textCase(nil) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { ArtBackdrop() }
            .navigationTitle("Queue")
            .searchable(text: $search, prompt: "Add a song from your playlist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    if let savedURL {
                        Link(destination: savedURL) { Label("Open", systemImage: "checkmark.circle.fill") }
                    } else {
                        Button {
                            Task { savedURL = await model.saveQueueAsPlaylist() }
                        } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        .disabled(model.queue.isEmpty || !model.canEditPlaylists)
                    }
                }
            }
        }
    }
}

private struct SongRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var highlight = false
    var addedByYou = false

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: track.artworkURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.body.weight(.medium)).lineLimit(1).foregroundStyle(highlight ? Theme.green : .white)
                Text(track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            if addedByYou { Image(systemName: "person.fill").font(.caption2).foregroundStyle(.white.opacity(0.6)) }
            if let mood = model.profiles[track.id]?.moods.first { MoodTag(mood: mood) }
        }
        .listRowBackground(Color.white.opacity(0.05))
    }
}

private struct RetagMenu: View {
    @Environment(AppModel.self) private var model
    let trackID: String

    var body: some View {
        Menu("This song is more…") {
            ForEach(Mood.allCases) { mood in
                Button(mood.title, systemImage: mood.symbol) { model.retag(trackID, as: mood) }
            }
        }
    }
}

// MARK: - Insights

private struct InsightsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemove = false

    var body: some View {
        let counts = Mood.allCases.map { mood in
            (mood: mood, count: model.tracks.filter { model.profiles[$0.id]?.moods.first == mood }.count)
        }
        NavigationStack {
            List {
                Section("Your playlist by mood") {
                    Chart(counts, id: \.mood) { item in
                        BarMark(x: .value("Songs", item.count), y: .value("Mood", item.mood.title))
                            .foregroundStyle(item.mood.color.gradient)
                            .cornerRadius(4)
                            .annotation(position: .trailing) { Text("\(item.count)").font(.caption2) }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 220)
                    if let thinnest = counts.min(by: { $0.count < $1.count }), thinnest.count < 25 {
                        Label("Only \(thinnest.count) \(thinnest.mood.title.lowercased()) songs, so \(thinnest.mood.title.lowercased()) mixes run short.",
                              systemImage: "lightbulb").font(.footnote)
                    }
                }
                Section("Most you") {
                    ForEach(Array(model.tracks.sorted { model.favorites.score(for: $0.id) > model.favorites.score(for: $1.id) }.prefix(5))) {
                        SongRow(track: $0)
                    }
                }
                Section("Duplicates") {
                    if !model.canEditPlaylists {
                        Button("Log in again to allow tidying playlists") {
                            Task { await model.logIn(with: WebAuthProvider()) }
                        }
                    } else if let found = model.duplicates {
                        if found.isEmpty {
                            Label("No duplicates", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                        } else {
                            ForEach(found) { Text("\($0.name) — \($0.artists) (×\($0.copies))").font(.footnote) }
                            Button("Remove extra copies…", role: .destructive) { confirmRemove = true }
                        }
                    } else {
                        Button("Check for duplicates") { Task { await model.findDuplicates() } }
                    }
                }
                Section("Move to another service") {
                    ExportButton(all: false)
                    ExportButton(all: true)
                }
            }
            .scrollContentBackground(.hidden)
            .background { ArtBackdrop() }
            .navigationTitle("Insights")
            .confirmationDialog("Remove the extra copies from \(model.selectedPlaylist?.name ?? "this playlist") in Spotify?",
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove extra copies", role: .destructive) { Task { await model.removeDuplicates() } }
            } message: {
                Text("One copy of each song stays where the first one was.")
            }
        }
    }
}

/// Builds the CSV (for TuneMyMusic / Soundiiz) and offers it through the share sheet.
private struct ExportButton: View {
    @Environment(AppModel.self) private var model
    let all: Bool
    @State private var file: URL?

    var body: some View {
        if let file {
            ShareLink(item: file) { Label("Share \(file.lastPathComponent)", systemImage: "square.and.arrow.up") }
        } else {
            Button(all ? "Export all playlists" : "Export this playlist", systemImage: "square.and.arrow.up") {
                Task {
                    let playlists = await model.exportPlaylists(all: all)
                    guard !playlists.isEmpty else { return }
                    let name = (all ? "MoodMix playlists" : playlists[0].name).replacingOccurrences(of: "/", with: "-")
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".csv")
                    try? PlaylistExport.csv(playlists).write(to: url, atomically: true, encoding: .utf8)
                    file = url
                }
            }
            .disabled(model.busy != nil)
        }
    }
}

// MARK: - Login & settings

private struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            VinylRecord(artworkURL: nil, spinning: true, size: 190)
                .padding(.bottom, 6)
            Text("MoodMix").font(.system(size: 44, weight: .black))
            Text("Mood-based, smoothly ordered mixes from your own Spotify playlists.")
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            Spacer()
            if model.clientID.isEmpty {
                Button("Add Spotify Client ID") { showSettings = true }
                    .font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(.white, in: .capsule)
            } else {
                Button(model.busy ?? "Log in with Spotify") { Task { await model.logIn(with: WebAuthProvider()) } }
                    .font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.green, in: .capsule)
                    .disabled(model.busy != nil)
                Button("Settings") { showSettings = true }.foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(28)
        .background { ArtBackdrop() }
    }
}

private struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("Client ID", text: $model.clientID).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: {
                    Text("Spotify")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.clientID.isEmpty && !model.clientIDLooksValid {
                            Label("That doesn't look like a Client ID (32 letters and digits).", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text("Use the same Client ID as on your Mac. It's the one labeled Client ID, not the Client secret. In your app at developer.spotify.com/dashboard, also add the Redirect URI moodmix://callback (keep the Mac one too).")
                    }
                }
                if model.isLoggedIn {
                    Section {
                        Button("Log in again") { Task { await model.logIn(with: WebAuthProvider()) } }
                        Button("Log out", role: .destructive) { Task { await model.logOut() } }
                    }
                }
                Section {
                    SecureField("Anthropic API key", text: $model.anthropicKey)
                    TextField("Model", text: $model.claudeModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: {
                    Text("Claude (mood labels)")
                } footer: {
                    Text("Each song is labeled once and saved on this phone.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
