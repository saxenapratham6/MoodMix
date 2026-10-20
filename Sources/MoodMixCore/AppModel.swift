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
    public var selectedPlaylistID: String? { didSet { UserDefaults.standard.set(selectedPlaylistID, forKey: "playlist.id") } }
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
    public private(set) var errorMessage: String?

    private var auth: SpotifyAuth
    private let store = ProfileStore()

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
        }
    }

    private var api: SpotifyAPI { SpotifyAPI(auth: auth) }

    public var selectedPlaylist: Playlist? { playlists.first { $0.id == selectedPlaylistID } }

    /// Tracks in the loaded playlist that have been analyzed.
    public var analyzedCount: Int { tracks.filter { profiles[$0.id] != nil }.count }

    // MARK: Actions

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
    }

    public func loadPlaylist() async {
        guard let id = selectedPlaylistID else { return }
        mix = []
        await run("Loading playlist…") {
            self.tracks = try await self.api.tracks(inPlaylist: id) { n in
                Task { @MainActor in self.busy = "Loading playlist… \(n) songs" }
            }
            self.busy = "Reading your favorites…"
            self.favorites = try await self.api.favoriteSignals()
        }
    }

    /// Fetches measured features, then has Claude label moods and fill gaps. Cached per track.
    public func analyze() async {
        let todo = tracks.filter { profiles[$0.id]?.moods.isEmpty ?? true }
        guard !todo.isEmpty else { return }
        await run("Fetching audio data…") {
            let measured = await ReccoBeatsClient().features(for: todo.map(\.id).filter { self.profiles[$0]?.featureSource != .reccobeats })
            var updates: [String: TrackProfile] = [:]
            for (id, f) in measured {
                updates[id] = TrackProfile(features: f, featureSource: .reccobeats, moods: self.profiles[id]?.moods ?? [])
            }
            await self.save(updates)

            guard !self.anthropicKey.isEmpty else {
                self.errorMessage = "Audio data found for \(measured.count) of \(todo.count) songs. Add an Anthropic API key in Settings to label moods for all of them."
                return
            }
            let tagger = ClaudeTagger(apiKey: self.anthropicKey, model: self.claudeModel)
            let batches = todo.chunked(into: 100)
            for (i, batch) in batches.enumerated() {
                self.busy = "Claude is labeling moods… batch \(i + 1) of \(batches.count)"
                let tags = try await tagger.tag(batch)
                var changes: [String: TrackProfile] = [:]
                for tag in tags where batch.contains(where: { $0.id == tag.id }) {
                    var p = self.profiles[tag.id] ?? TrackProfile()
                    p.moods = tag.moods
                    p.genre = tag.genre
                    if p.featureSource != .reccobeats {
                        p.features = AudioFeatures(energy: tag.energy.clamped, valence: tag.valence.clamped,
                                                   tempo: tag.tempo, key: tag.key, mode: tag.mode)
                        p.featureSource = .claude
                    }
                    changes[tag.id] = p
                }
                await self.save(changes)
            }
        }
    }

    public func buildMix() {
        let request = MixRequest(mood: mood, minutes: minutes, favoriteWeight: favoriteWeight, arc: arc)
        mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: favorites, request: request)
        if mix.isEmpty { errorMessage = "No songs in this playlist fit “\(mood.title)” yet. Try analyzing the playlist or another mood." }
    }

    public func playMix() async {
        await run("Starting playback…") {
            try await self.api.play(uris: self.mix.map(\.track.uri))
        }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: Helpers

    private func loadLibrary() async throws {
        playlists = try await api.myPlaylists()
        if selectedPlaylistID != nil, tracks.isEmpty { await loadPlaylist() }
    }

    private func save(_ changes: [String: TrackProfile]) async {
        guard !changes.isEmpty else { return }
        profiles.merge(changes) { _, new in new }
        await store.update(changes)
    }

    private func rebuildAuth() { auth = SpotifyAuth(clientID: clientID) }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        busy = label
        errorMessage = nil
        do { try await work() } catch { errorMessage = error.localizedDescription }
        busy = nil
    }
}

extension Double {
    var clamped: Double { Swift.min(Swift.max(self, 0), 1) }
}
