import Foundation
import Observation

/// Shared state and actions for the macOS and (later) iOS apps.
@MainActor @Observable
public final class AppModel {
    // Settings
    public var clientID: String { didSet { UserDefaults.standard.set(clientID, forKey: "spotify.clientID"); rebuildAuth() } }
    public var anthropicKey: String { didSet { Keychain.set(anthropicKey, for: "anthropic.apiKey") } }
    public var claudeModel: String { didSet { UserDefaults.standard.set(claudeModel, forKey: "claude.model") } }

    // Library
    public private(set) var isLoggedIn = false
    public private(set) var playlists: [Playlist] = []
    public var selectedPlaylistID: String? {
        didSet {
            guard selectedPlaylistID != oldValue else { return }
            UserDefaults.standard.set(selectedPlaylistID, forKey: "playlist.id")
            Task { await loadPlaylist() }
        }
    }
    public private(set) var tracks: [Track] = []
    public private(set) var profiles: [String: TrackProfile] = [:]
    public private(set) var favorites = FavoriteSignals()

    // Mix
    public var mood: Mood = .chill
    public var arc: EnergyArc = .steady
    public var minutes = 60
    public var favoriteWeight = 0.4
    public private(set) var mix: [MixEntry] = []

    // Status
    public private(set) var busy: String?
    /// Mood labeling runs in the background without blocking the rest of the app.
    public private(set) var analysisStatus: String?
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var errorMessage: String?

    private var auth: SpotifyAuth
    private let store = ProfileStore()
    private var snapshotID: String?
    private var analyzing = false

    public init() {
        clientID = UserDefaults.standard.string(forKey: "spotify.clientID") ?? ""
        anthropicKey = Keychain.get("anthropic.apiKey") ?? ""
        claudeModel = UserDefaults.standard.string(forKey: "claude.model") ?? ClaudeTagger.defaultModel
        selectedPlaylistID = UserDefaults.standard.string(forKey: "playlist.id")
        auth = SpotifyAuth(clientID: UserDefaults.standard.string(forKey: "spotify.clientID") ?? "")
        Task {
            profiles = await store.all()
            isLoggedIn = await auth.isLoggedIn
            if isLoggedIn { await run("Loading playlists…") { try await self.loadLibrary() } }
            await backgroundLoop()
        }
    }

    private var api: SpotifyAPI { SpotifyAPI(auth: auth) }

    public var selectedPlaylist: Playlist? { playlists.first { $0.id == selectedPlaylistID } }

    /// Songs Claude has given mood labels to.
    public var taggedCount: Int { tracks.filter { !(profiles[$0.id]?.moods.isEmpty ?? true) }.count }
    public var favoriteCount: Int { tracks.filter { favorites.score(for: $0.id) > 0 }.count }
    public var needsAnalysis: Bool { taggedCount < tracks.count }

    // MARK: Account

    public func logIn(with provider: AuthCodeProvider) async {
        await run("Waiting for Spotify login in your browser…") {
            try await self.auth.logIn(using: provider)
            self.isLoggedIn = true
            try await self.loadLibrary()
        }
    }

    public func logOut() async {
        await auth.logOut()
        isLoggedIn = false
        playlists = []
        tracks = []
        mix = []
        nowPlaying = nil
    }

    // MARK: Playlist

    public func loadPlaylist() async {
        guard isLoggedIn, let id = selectedPlaylistID else { return }
        mix = []
        await run("Loading playlist…") {
            self.snapshotID = try? await self.api.playlistSnapshot(id)
            self.tracks = try await self.api.tracks(inPlaylist: id) { n in
                Task { @MainActor in self.busy = "Loading playlist… \(n) songs" }
            }
            self.busy = "Reading your favorites…"
            self.favorites = try await self.api.favoriteSignals()
        }
        await analyze()
    }

    /// Re-reads the playlist if it changed in Spotify, then labels any new songs.
    func syncIfPlaylistChanged() async {
        guard isLoggedIn, busy == nil, !analyzing, let id = selectedPlaylistID,
              let snapshot = try? await api.playlistSnapshot(id), snapshot != snapshotID else { return }
        guard let fresh = try? await api.tracks(inPlaylist: id) else { return }
        let known = Set(tracks.map(\.id))
        let added = fresh.filter { !known.contains($0.id) }.count
        tracks = fresh
        snapshotID = snapshot
        if added > 0 { analysisStatus = "\(added) new song\(added == 1 ? "" : "s") found in Spotify" }
        await analyze()
        if let i = playlists.firstIndex(where: { $0.id == id }) {
            let p = playlists[i]
            playlists[i] = Playlist(id: p.id, name: p.name, trackCount: fresh.count, imageURL: p.imageURL, snapshotID: snapshot)
        }
    }

    // MARK: Analysis

    /// Fetches measured features, then has Claude label moods and fill gaps. Only untagged songs are sent.
    public func analyze() async {
        guard !analyzing else { return }
        let todo = tracks.filter { profiles[$0.id]?.moods.isEmpty ?? true }
        guard !todo.isEmpty else { return }
        analyzing = true
        defer { analyzing = false }

        analysisStatus = "Fetching audio data for \(todo.count) songs…"
        let needFeatures = todo.map(\.id).filter { profiles[$0]?.featureSource != .reccobeats }
        let measured = await ReccoBeatsClient().features(for: needFeatures)
        await save(measured.mapValues { f in TrackProfile(features: f, featureSource: .reccobeats) })

        guard !anthropicKey.isEmpty else {
            analysisStatus = nil
            errorMessage = "Add an Anthropic API key in Settings (⌘,) so MoodMix can label each song's mood."
            return
        }

        let tagger = ClaudeTagger(apiKey: anthropicKey, model: claudeModel)
        let batches = todo.chunked(into: 50)
        var done = 0
        var failures: [String] = []
        analysisStatus = "Labeling moods… 0 of \(todo.count)"
        // Four requests at a time keeps a 1,000-song playlist to a couple of minutes.
        for wave in batches.chunked(into: 4) {
            let results = await withTaskGroup(of: (batch: [Track], result: Result<[ClaudeTagger.Tag], Error>).self) { group in
                for batch in wave {
                    group.addTask { (batch, await Result { try await tagger.tag(batch) }) }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
            for (batch, result) in results {
                switch result {
                case .success(let tags): await apply(tags, to: batch)
                case .failure(let error): failures.append(error.localizedDescription)
                }
                done += batch.count
            }
            analysisStatus = "Labeling moods… \(min(done, todo.count)) of \(todo.count)"
        }
        analysisStatus = nil
        if !failures.isEmpty {
            errorMessage = "Some songs couldn't be labeled (\(failures.count) batch\(failures.count == 1 ? "" : "es")): \(failures[0])"
        }
    }

    private func apply(_ tags: [ClaudeTagger.Tag], to batch: [Track]) async {
        let ids = Set(batch.map(\.id))
        var changes: [String: TrackProfile] = [:]
        for tag in tags where ids.contains(tag.id) {
            var p = profiles[tag.id] ?? TrackProfile()
            p.moods = tag.moods
            p.genre = tag.genre
            if p.featureSource != .reccobeats {
                p.features = AudioFeatures(energy: tag.energy.clamped, valence: tag.valence.clamped,
                                           tempo: tag.tempo, key: tag.key, mode: tag.mode)
                p.featureSource = .claude
            }
            changes[tag.id] = p
        }
        await save(changes)
    }

    // MARK: Mix & playback

    public func buildMix() {
        let request = MixRequest(mood: mood, minutes: minutes, favoriteWeight: favoriteWeight, arc: arc)
        mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: favorites, request: request)
        if mix.isEmpty { errorMessage = "No songs in this playlist fit “\(mood.title)” yet. Wait for mood labeling to finish, or try another mood." }
    }

    /// Plays the mix from `index`, building one first if needed.
    public func playMix(from index: Int = 0) async {
        if mix.isEmpty { buildMix() }
        guard index < mix.count else { return }
        await play(mix[index...].map(\.track))
    }

    public func play(_ tracks: [Track]) async {
        await run("Starting playback…") {
            try await self.api.play(uris: tracks.map(\.uri))
        }
        await refreshPlayback()
    }

    public func togglePlayPause() async {
        guard let np = nowPlaying else { return }
        await control { np.isPlaying ? try await $0.pause() : try await $0.resume() }
    }

    public func skipNext() async { await control { try await $0.next() } }
    public func skipPrevious() async { await control { try await $0.previous() } }

    public func dismissError() { errorMessage = nil }

    // MARK: Helpers

    /// Polls playback every 2 s and checks the playlist for changes every minute.
    private func backgroundLoop() async {
        var tick = 0
        while !Task.isCancelled {
            if isLoggedIn {
                await refreshPlayback()
                if tick % 30 == 29 { await syncIfPlaylistChanged() }
            }
            tick += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refreshPlayback() async {
        guard isLoggedIn, let state = try? await api.currentPlayback() else { return }
        nowPlaying = state
    }

    private func control(_ action: @escaping (SpotifyAPI) async throws -> Void) async {
        do { try await action(api) } catch { errorMessage = error.localizedDescription }
        try? await Task.sleep(for: .milliseconds(300))
        await refreshPlayback()
    }

    private func loadLibrary() async throws {
        playlists = try await api.myPlaylists()
        if selectedPlaylistID != nil, tracks.isEmpty { Task { await loadPlaylist() } }
    }

    private func save(_ changes: [String: TrackProfile]) async {
        guard !changes.isEmpty else { return }
        profiles.merge(changes) { old, new in
            // Never let a features-only update wipe out mood labels we already have.
            var merged = new
            if merged.moods.isEmpty { merged.moods = old.moods; merged.genre = old.genre }
            return merged
        }
        await store.update(Dictionary(uniqueKeysWithValues: changes.keys.compactMap { id in profiles[id].map { (id, $0) } }))
    }

    private func rebuildAuth() { auth = SpotifyAuth(clientID: clientID) }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        busy = label
        errorMessage = nil
        do { try await work() } catch { errorMessage = error.localizedDescription }
        busy = nil
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

extension Double {
    var clamped: Double { Swift.min(Swift.max(self, 0), 1) }
}
