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

    /// Journey mode: the mix travels through `journey`'s moods in order.
    public var journeyMode = false
    public private(set) var journey: [Mood] = []

    /// Let MoodMix pick the mood from the time of day, your headphones and your habits.
    public var autoMood: Bool { didSet { UserDefaults.standard.set(autoMood, forKey: "mood.auto"); updateSuggestion() } }
    public private(set) var suggestion: MoodSuggester.Suggestion?
    /// Platform hook describing the moment (macOS adds whether headphones are connected).
    @ObservationIgnored public var momentProvider: (() -> MomentContext)?

    public private(set) var sleepTimer: SleepTimer = .off
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// The last song of the mix you generated, for "stop at end of mix".
    @ObservationIgnored private var mixEndTrackID: String?

    // Status
    public private(set) var busy: String?
    /// Mood labeling runs in the background without blocking the rest of the app.
    public private(set) var analysisStatus: String?
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var errorMessage: String?

    /// Platform hook run before playback, e.g. launching the Spotify app on macOS.
    @ObservationIgnored public var beforePlayback: (@MainActor () async -> Void)?

    /// MoodMix's own queue. `queueActive` is false when Spotify is playing something else.
    public private(set) var queue = PlayQueue()
    public private(set) var queueActive = false
    @ObservationIgnored private var resendTask: Task<Void, Never>?
    @ObservationIgnored private var pendingResend = false

    /// When Spotify's quota resets, while MoodMix is backing off.
    public private(set) var rateLimitedUntil: Date?

    private var auth: SpotifyAuth
    private let store = ProfileStore()
    private let libraryCache = LibraryCache()
    private var library = LibrarySnapshot()
    private var analyzing = false
    private var lastLibraryAttempt = Date.distantPast

    public init() {
        clientID = UserDefaults.standard.string(forKey: "spotify.clientID") ?? ""
        anthropicKey = Keychain.get("anthropic.apiKey") ?? ""
        claudeModel = UserDefaults.standard.string(forKey: "claude.model") ?? ClaudeTagger.defaultModel
        autoMood = UserDefaults.standard.bool(forKey: "mood.auto")
        selectedPlaylistID = UserDefaults.standard.string(forKey: "playlist.id")
        auth = SpotifyAuth(clientID: UserDefaults.standard.string(forKey: "spotify.clientID") ?? "")
        Task {
            profiles = await store.all()
            // Show the saved library instantly; refresh from Spotify after.
            library = await libraryCache.load()
            playlists = library.playlists
            favorites = library.favorites ?? FavoriteSignals()
            if let id = selectedPlaylistID, let cached = library.tracks[id] { tracks = cached.tracks }
            isLoggedIn = await auth.isLoggedIn
            canEditPlaylists = await auth.hasScope("playlist-modify-private")
            if isLoggedIn { await refreshLibrary() }
            await backgroundLoop()
        }
    }

    private var api: SpotifyAPI { SpotifyAPI(auth: auth) }

    public var selectedPlaylist: Playlist? { playlists.first { $0.id == selectedPlaylistID } }

    /// Songs Claude has given mood labels to.
    public var taggedCount: Int { tracks.filter { !(profiles[$0.id]?.moods.isEmpty ?? true) }.count }
    public var favoriteCount: Int { tracks.filter { favorites.score(for: $0.id) > 0 }.count }
    public var needsAnalysis: Bool { taggedCount < tracks.count }
    /// Playlist entries MoodMix doesn't count: the same song added twice, local files, podcasts.
    public var skippedCount: Int { max(0, (selectedPlaylist?.trackCount ?? 0) - tracks.count) }

    /// Re-checks Spotify for playlist changes if it hasn't recently (e.g. when the widget opens).
    public func refreshIfStale() {
        guard isLoggedIn, busy == nil, Date().timeIntervalSince(lastLibraryAttempt) > 20 else { return }
        Task { await refreshLibrary() }
    }

    // MARK: Account

    public func logIn(with provider: AuthCodeProvider) async {
        await run("Waiting for Spotify login in your browser…") {
            try await self.auth.logIn(using: provider)
            self.isLoggedIn = true
            self.canEditPlaylists = await self.auth.hasScope("playlist-modify-private")
        }
        if isLoggedIn { await refreshLibrary() }
    }

    public func logOut() async {
        await auth.logOut()
        isLoggedIn = false
        playlists = []
        tracks = []
        mix = []
        nowPlaying = nil
        library = LibrarySnapshot()
        await libraryCache.save(library)
    }

    // MARK: Playlist

    /// Refreshes the playlist list (one request), then the selected playlist's songs only if they changed.
    public func refreshLibrary() async {
        guard isLoggedIn else { return }
        lastLibraryAttempt = Date()
        let label = playlists.isEmpty ? "Loading playlists…" : nil
        await run(label) {
            self.playlists = try await self.api.myPlaylists()
            self.library.playlists = self.playlists
            await self.libraryCache.save(self.library)
        }
        await loadPlaylist()
    }

    /// Uses the saved songs when the playlist hasn't changed; otherwise downloads it again.
    public func loadPlaylist() async {
        guard isLoggedIn, let id = selectedPlaylistID else { return }
        let cached = library.tracks[id]
        if let cached, tracks.map(\.id) != cached.tracks.map(\.id) {
            tracks = cached.tracks
            mix = []
        }
        let snapshot = playlists.first { $0.id == id }?.snapshotID
        let needsTracks = cached == nil || snapshot == nil || cached?.snapshotID != snapshot
        let needsFavorites = library.favorites == nil || (library.favoritesFetchedAt ?? .distantPast) < Date().addingTimeInterval(-6 * 3600)
        guard needsTracks || needsFavorites else {
            await analyze()
            return
        }

        await run(cached == nil ? "Loading playlist…" : nil) {
            if needsTracks {
                let known = Set(cached?.tracks.map(\.id) ?? [])
                let fresh = try await self.api.tracks(inPlaylist: id) { n in
                    Task { @MainActor in if cached == nil { self.busy = "Loading playlist… \(n) songs" } }
                }
                guard self.selectedPlaylistID == id else { return }
                if cached != nil {
                    let added = fresh.filter { !known.contains($0.id) }.count
                    if added > 0 { self.analysisStatus = "\(added) new song\(added == 1 ? "" : "s") found in Spotify" }
                } else {
                    self.mix = []
                }
                self.tracks = fresh
                self.library.tracks[id] = .init(snapshotID: snapshot, tracks: fresh)
                await self.libraryCache.save(self.library)
            }
            if needsFavorites {
                if cached == nil { self.busy = "Reading your favorites…" }
                self.favorites = try await self.api.favoriteSignals()
                self.library.favorites = self.favorites
                self.library.favoritesFetchedAt = Date()
                await self.libraryCache.save(self.library)
            }
        }
        await analyze()
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
        queue.start(mix[index...].map(\.track), mood: mood)
        await sendQueue(positionMs: 0)
    }

    /// A fresh mix for the selected mood (or journey), played right away as MoodMix's queue.
    public func generate() async {
        var queueMood = mood
        if journeyMode && journey.count >= 2 {
            mix = MixBuilder.buildJourney(journey, tracks: tracks, profiles: profiles, favorites: favorites,
                                          minutes: minutes, favoriteWeight: favoriteWeight)
            queueMood = journey.last!
            if mix.isEmpty { errorMessage = "Not enough songs in this playlist for that journey yet." }
        } else {
            if autoMood {
                updateSuggestion()
                if let suggestion { mood = suggestion.mood }
            } else {
                rememberPick(mood)
            }
            queueMood = mood
            buildMix()
        }
        guard !mix.isEmpty else { return }
        mixEndTrackID = mix.last?.track.id
        queue.start(mix.map(\.track), mood: queueMood)
        await sendQueue(positionMs: 0)
    }

    /// Journey mode: tapping a mood adds it to the route (up to 4), tapping it again removes it.
    public func toggleJourneyMood(_ mood: Mood) {
        if let i = journey.firstIndex(of: mood) {
            journey.remove(at: i)
        } else if journey.count < 4 {
            journey.append(mood)
        }
    }

    public func clearJourney() { journey = [] }

    // MARK: Mood from the moment

    public func updateSuggestion() {
        let context = momentProvider?() ?? MomentContext()
        let next = MoodSuggester.suggest(for: context, history: moodHistory)
        if next.mood != suggestion?.mood || next.reason != suggestion?.reason { suggestion = next }
    }

    private var moodHistory: [MoodPick] {
        guard let data = UserDefaults.standard.data(forKey: "mood.history") else { return [] }
        return (try? JSONDecoder().decode([MoodPick].self, from: data)) ?? []
    }

    private func rememberPick(_ mood: Mood) {
        let history = (moodHistory + [MoodPick(date: Date(), mood: mood)]).suffix(300)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(history)), forKey: "mood.history")
    }

    // MARK: Playlists you can keep

    /// False for logins made before MoodMix asked to edit playlists; log in again to allow it.
    public private(set) var canEditPlaylists = false
    public private(set) var duplicates: [SpotifyAPI.Duplicate]?

    /// Saves what's queued (or the last mix) as a private playlist in your Spotify library.
    public func saveQueueAsPlaylist() async -> URL? {
        let songs = queue.isEmpty ? mix.map(\.track) : [queue.current!.track] + queue.upcoming.map(\.track)
        guard !songs.isEmpty else { return nil }
        let moodName = journeyMode && journey.count >= 2 ? journey.map(\.title).joined(separator: " → ") : (queue.mood ?? mood).title
        let name = "MoodMix · \(moodName) · \(Date().formatted(.dateTime.month(.abbreviated).day()))"
        let description = "\(songs.count) songs from \(selectedPlaylist?.name ?? "my playlist"), mixed by MoodMix."
        var url: URL?
        await run("Saving playlist…") {
            url = try await self.api.createPlaylist(name: name, description: description, uris: songs.map(\.uri))
            ActivityLog.write("saved playlist \(name) with \(songs.count) songs")
            self.playlists = try await self.api.myPlaylists()
            self.library.playlists = self.playlists
            await self.libraryCache.save(self.library)
        }
        return url
    }

    /// Looks up which songs appear more than once in the selected playlist.
    public func findDuplicates() async {
        guard let id = selectedPlaylistID else { return }
        await run("Checking for duplicates…") {
            self.duplicates = try await self.api.duplicates(inPlaylist: id)
        }
    }

    /// Removes extra copies from the playlist in Spotify, keeping one copy where the first one was.
    public func removeDuplicates() async {
        guard let id = selectedPlaylistID, let duplicates, !duplicates.isEmpty else { return }
        await run("Removing \(duplicates.count) duplicates…") {
            try await self.api.removeDuplicates(duplicates, inPlaylist: id)
            ActivityLog.write("removed duplicates: \(duplicates.map(\.name).joined(separator: ", "))")
            self.duplicates = []
        }
        await refreshLibrary()
    }

    // MARK: Export

    /// Downloads the selected playlist (or all of them) fresh, with ISRCs, ready to write as CSV/JSON.
    public func exportPlaylists(all: Bool) async -> [PlaylistExport.Playlist] {
        let targets = all ? playlists : playlists.filter { $0.id == selectedPlaylistID }
        var result: [PlaylistExport.Playlist] = []
        await run("Exporting \(targets.count) playlist\(targets.count == 1 ? "" : "s")…") {
            for (i, playlist) in targets.enumerated() {
                self.busy = "Exporting \(playlist.name) (\(i + 1) of \(targets.count))…"
                let songs = try await self.api.tracks(inPlaylist: playlist.id)
                result.append(PlaylistExport.playlist(name: playlist.name, id: playlist.id, tracks: songs, profiles: self.profiles))
            }
        }
        ActivityLog.write("exported \(result.count) playlists")
        return result
    }

    // MARK: Your corrections

    /// "This song is more <mood>": puts that mood first for the song and keeps analysis from changing it.
    public func retag(_ trackID: String, as mood: Mood) {
        var profile = profiles[trackID] ?? TrackProfile()
        profile.moods = [mood] + profile.moods.filter { $0 != mood }
        profile.userTagged = true
        var feedback = profile.feedback ?? [:]
        feedback[mood.rawValue] = max(feedback[mood.rawValue] ?? 0, 0)
        profile.feedback = feedback
        Task { await save([trackID: profile]) }
        ActivityLog.write("retagged \(trackID) as \(mood.rawValue)")
    }

    // MARK: Sleep timer

    public enum SleepOption: Hashable, Sendable {
        case off, endOfSong, endOfMix, minutes(Int)
    }

    public func setSleepTimer(_ option: SleepOption) {
        sleepTask?.cancel()
        switch option {
        case .off:
            sleepTimer = .off
        case .endOfSong:
            guard let id = nowPlaying?.track.id else { return }
            sleepTimer = .endOfSong(trackID: id)
        case .endOfMix:
            guard let id = mixEndTrackID ?? queue.upcoming.last?.track.id ?? nowPlaying?.track.id else { return }
            sleepTimer = .endOfMix(trackID: id)
        case .minutes(let m):
            sleepTimer = .at(Date().addingTimeInterval(TimeInterval(m * 60)))
        }
        guard sleepTimer.isOn else { return }
        ActivityLog.write("sleep timer: \(sleepTimer)")
        sleepTask = Task { await runSleepTimer() }
    }

    /// Text for the widget, e.g. "Stops in 23 min".
    public var sleepTimerText: String? {
        switch sleepTimer {
        case .off: return nil
        case .endOfSong: return "Stops after this song"
        case .endOfMix: return "Stops at the end of the mix"
        case .at(let date):
            let minutes = Int((date.timeIntervalSinceNow / 60).rounded(.up))
            return minutes <= 1 ? "Stopping in under a minute" : "Stops in \(minutes) min"
        }
    }

    private func runSleepTimer() async {
        while !Task.isCancelled, sleepTimer.isOn {
            try? await Task.sleep(for: .seconds(1))
            guard let np = nowPlaying else { continue }
            switch sleepTimer {
            case .off:
                return
            case .endOfSong(let id), .endOfMix(let id):
                if np.track.id != id {
                    // Already past it (a skip, or the 5 s poll missed the end).
                    if case .endOfSong = sleepTimer { await sleepNow(fade: false); return }
                    continue
                }
                let remaining = np.track.durationMs - np.progress(at: Date())
                if np.isPlaying && remaining < 1_200 {
                    try? await Task.sleep(for: .milliseconds(max(remaining - 300, 0)))
                    await sleepNow(fade: false)
                    return
                }
            case .at(let date):
                if date.timeIntervalSinceNow <= 20 {
                    await sleepNow(fade: true)
                    return
                }
            }
        }
    }

    /// Pauses, optionally fading the volume down over ~20 s first (and restoring it after).
    private func sleepNow(fade: Bool) async {
        let api = self.api
        let original = (try? await api.currentPlayback())?.volumePercent ?? nowPlaying?.volumePercent
        if fade, let original, original > 0 {
            for step in stride(from: 9, through: 0, by: -1) {
                guard sleepTimer.isOn else { return }
                try? await api.setVolume(original * step / 10)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        try? await api.pause()
        if fade, let original { try? await api.setVolume(original) }
        ActivityLog.write("sleep timer: paused")
        sleepTimer = .off
        await refreshPlayback()
    }

    /// Takes the mood of the song playing now and lines up matching songs from the playlist after it,
    /// without restarting it.
    public func matchCurrentSong() async {
        guard let np = nowPlaying else {
            errorMessage = "Play something first, then Match finds songs from your playlist that fit it."
            return
        }
        if let topMood = profiles[np.track.id]?.moods.first { mood = topMood }
        let inPlaylist = tracks.contains { $0.id == np.track.id }
        let request = MixRequest(mood: mood, minutes: minutes, favoriteWeight: favoriteWeight, arc: arc,
                                 startTrackID: inPlaylist ? np.track.id : nil)
        mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: favorites, request: request)
        let rest = mix.map(\.track).filter { $0.id != np.track.id }
        guard !rest.isEmpty else { return }
        queue.start([np.track] + rest, mood: mood)
        await sendQueue(positionMs: currentProgress)
    }

    public func play(_ tracks: [Track]) async {
        queue.start(tracks, mood: mood)
        await sendQueue(positionMs: 0)
    }

    // MARK: Queue

    public func moveInQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        scheduleResend()
    }

    public func removeFromQueue(_ id: UUID) {
        queue.remove(id)
        scheduleResend()
    }

    /// Adds any song from the playlist right after the current one. The queue's mood carries on after it.
    public func playNext(_ track: Track) {
        guard !queue.isEmpty else {
            Task { await play([track]) }
            return
        }
        queue.playNext(track)
        scheduleResend()
    }

    public func addToQueueEnd(_ track: Track) {
        guard !queue.isEmpty else {
            Task { await play([track]) }
            return
        }
        queue.addToEnd(track)
        scheduleResend()
    }

    public func jumpInQueue(to id: UUID) async {
        guard queue.jump(to: id) else { return }
        await sendQueue(positionMs: 0)
    }

    /// Picks the queue back up after you played something else in Spotify.
    public func resumeQueue() async {
        await sendQueue(positionMs: 0, reason: "resume queue")
    }

    /// Songs in the playlist matching a search, for adding to the queue.
    public func searchPlaylist(_ text: String, limit: Int = 8) -> [Track] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return Array(tracks.lazy.filter { track in
            let haystack = (track.name + " " + track.artistLine + " " + track.album).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }.prefix(limit))
    }

    /// Edits are batched briefly, then the new order is sent to Spotify, continuing the current song.
    private func scheduleResend() {
        resendTask?.cancel()
        guard queueActive else { return }
        resendTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            resendTask = nil
            // Sending the queue starts playback, so never do it behind a paused player's back.
            guard nowPlaying?.isPlaying == true else {
                pendingResend = true
                ActivityLog.write("queue edited while paused; will send when playback resumes")
                return
            }
            await sendQueue(positionMs: currentProgress, reason: "queue edited")
        }
    }

    private var currentProgress: Int {
        guard let np = nowPlaying, np.track.id == queue.current?.track.id else { return 0 }
        return np.progress(at: Date()) + 250  // allow for request latency
    }

    private func sendQueue(positionMs: Int, reason: String = "start") async {
        guard !queue.isEmpty else { return }
        let uris = queue.uris
        pendingResend = false
        ActivityLog.write("play \(uris.count) songs from \(queue.current?.track.name ?? "?") at \(positionMs / 1000)s (\(reason))")
        await run(queueActive ? nil : "Starting playback…") {
            await self.beforePlayback?()
            try await self.api.play(uris: uris, positionMs: positionMs)
            self.queue.markSent()
            self.queueActive = true
        }
        await refreshPlayback()
    }

    /// Keeps the queue in step with Spotify and topped up with songs in its mood.
    private func followQueue(previous: NowPlaying? = nil) async {
        guard queueActive, let np = nowPlaying else { return }
        // You started a playlist/album in Spotify yourself: hands off, even if its songs are also in the queue.
        if let context = np.contextURI {
            queueActive = false
            resendTask?.cancel()
            resendTask = nil
            ActivityLog.write("Spotify is playing \(context); MoodMix stepped back")
            return
        }
        let leaving = queue.current
        let upcomingIDs = Set(queue.upcoming.map(\.track.id))
        guard queue.follow(playingTrackID: np.track.id) else {
            queueActive = false  // you started something else in Spotify
            ActivityLog.write("Spotify is playing \(np.track.name), not in the queue; MoodMix stepped back")
            return
        }
        // Moved forward through the queue: learn from how the previous song went.
        if leaving?.track.id != np.track.id, upcomingIDs.contains(np.track.id) {
            learnFromTransition(previous: previous, leaving: leaving)
        }
        if queue.needsMore, let mood = queue.mood {
            let used = queue.trackIDs
            let anchor = queue.upcoming.last?.track ?? queue.current?.track
            let request = MixRequest(mood: mood, minutes: 45, favoriteWeight: favoriteWeight, arc: .steady, startTrackID: anchor?.id)
            var more = MixBuilder.build(tracks: tracks.filter { !used.contains($0.id) || $0.id == anchor?.id },
                                        profiles: profiles, favorites: favorites, request: request)
                .map(\.track).filter { !used.contains($0.id) }
            if more.isEmpty {
                // Every song in this mood has played; start the mood over.
                more = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: favorites, request: request)
                    .map(\.track).filter { $0.id != queue.current?.track.id }
            }
            queue.extend(with: Array(more.prefix(12)))
        }
        // Only touch playback while it's playing; sending the queue would otherwise un-pause it.
        guard np.isPlaying, resendTask == nil else { return }
        if pendingResend {
            await sendQueue(positionMs: currentProgress, reason: "edits made while paused")
        } else if queue.needsResend {
            // Spotify is on the last song it was given: hand it the rest while this one is still early.
            await sendQueue(positionMs: currentProgress, reason: "topping up the queue")
        }
    }

    /// Asks Spotify for its live state first, since the 5-second poll can be stale
    /// (pausing an already-paused player is refused).
    public func togglePlayPause() async {
        await control { api in
            let playing = (try? await api.currentPlayback())?.isPlaying ?? self.nowPlaying?.isPlaying ?? false
            ActivityLog.write(playing ? "pause (button)" : "resume (button)")
            playing ? try await api.pause() : try await api.resume()
        }
    }

    public func skipNext() async {
        ActivityLog.write("next (button)")
        await control { try await $0.next() }
    }

    public func skipPrevious() async {
        ActivityLog.write("previous (button)")
        await control { try await $0.previous() }
    }

    public func dismissError() { errorMessage = nil }

    /// One line for the widget: what MoodMix is doing right now, if anything.
    public var statusLine: String? {
        if let until = rateLimitedUntil {
            return "Spotify asked us to slow down · back at \(until.formatted(date: .omitted, time: .shortened))"
        }
        return busy ?? analysisStatus
    }

    // MARK: Helpers

    /// Polls playback every 5 s and checks for playlist edits every 2 minutes, pausing while rate-limited.
    private func backgroundLoop() async {
        var tick = 0
        while !Task.isCancelled {
            rateLimitedUntil = await RateLimit.shared.blockedUntil
            if tick % 12 == 0 { updateSuggestion() }
            if isLoggedIn, rateLimitedUntil == nil {
                await refreshPlayback()
                let libraryMissing = playlists.isEmpty || (selectedPlaylistID != nil && tracks.isEmpty)
                if libraryMissing, busy == nil, Date().timeIntervalSince(lastLibraryAttempt) > 30 {
                    await refreshLibrary()
                } else if tick % 24 == 23, busy == nil, !analyzing {
                    await refreshLibrary()
                }
            }
            tick += 1
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func refreshPlayback() async {
        guard isLoggedIn, let state = try? await api.currentPlayback() else { return }
        let previous = nowPlaying
        nowPlaying = state
        await followQueue(previous: previous)
    }

    /// When the queue moves on, how far the last song got tells us whether it fit the mood.
    private func learnFromTransition(previous: NowPlaying?, leaving item: QueueItem?) {
        guard let item, !item.addedByYou, let mood = queue.mood,
              let previous, previous.track.id == item.track.id,
              let outcome = ListeningOutcome.judge(playedMs: previous.progress(at: Date()), durationMs: item.track.durationMs)
        else { return }
        var profile = profiles[item.track.id] ?? TrackProfile()
        profile.learn(outcome, mood: mood)
        Task { await save([item.track.id: profile]) }
        ActivityLog.write("\(outcome == .skipped ? "skipped" : "finished") \(item.track.name) (\(mood.rawValue))")
    }

    private func control(_ action: @escaping (SpotifyAPI) async throws -> Void) async {
        do {
            try await action(api)
        } catch SpotifyError.restricted {
            // Harmless: the button didn't apply to the player's current state. The refresh below shows the truth.
        } catch SpotifyError.rateLimited(let until) {
            rateLimitedUntil = until
        } catch {
            errorMessage = error.localizedDescription
        }
        try? await Task.sleep(for: .milliseconds(300))
        await refreshPlayback()
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

    private func run(_ label: String?, _ work: @escaping () async throws -> Void) async {
        if let label { busy = label }
        errorMessage = nil
        do {
            try await work()
        } catch SpotifyError.rateLimited(let until) {
            rateLimitedUntil = until
        } catch {
            errorMessage = error.localizedDescription
        }
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
