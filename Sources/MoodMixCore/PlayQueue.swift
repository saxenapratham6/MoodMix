import Foundation

public struct QueueItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let track: Track
    /// Added by hand rather than picked for the mood.
    public let addedByYou: Bool

    public init(track: Track, addedByYou: Bool = false) {
        id = UUID()
        self.track = track
        self.addedByYou = addedByYou
    }
}

/// MoodMix's own play queue.
///
/// Spotify's Web API can't reorder or remove queued songs (and its own queue survives new playback,
/// so it can't be cleared either). MoodMix therefore keeps the real order here, sends it to Spotify
/// as the list to play, and re-sends it whenever it changes. It follows what Spotify actually plays
/// so skips and "previous" stay in sync.
public struct PlayQueue: Sendable {
    public private(set) var current: QueueItem?
    public private(set) var upcoming: [QueueItem] = []
    public private(set) var history: [QueueItem] = []
    /// The mood the queue keeps topping itself up with, whatever songs get added by hand.
    public private(set) var mood: Mood?
    /// How many of `upcoming` Spotify already has, in order, after the current song.
    public private(set) var sentAhead = 0

    public static let maxSent = 99

    public init() {}

    public var isEmpty: Bool { current == nil }
    /// Fewer than this many songs left → add more songs in the queue's mood.
    public var needsMore: Bool { current != nil && upcoming.count < 3 }
    /// Spotify is on the last song we sent, but we have more queued.
    public var needsResend: Bool { sentAhead == 0 && !upcoming.isEmpty }

    /// Every track the queue has played, is playing, or will play.
    public var trackIDs: Set<String> {
        Set(history.map(\.track.id) + upcoming.map(\.track.id) + (current.map { [$0.track.id] } ?? []))
    }

    /// The list to hand Spotify: current song first.
    public var uris: [String] {
        guard let current else { return [] }
        return [current.track.uri] + upcoming.prefix(Self.maxSent).map(\.track.uri)
    }

    public mutating func start(_ tracks: [Track], mood: Mood) {
        history = []
        current = tracks.first.map { QueueItem(track: $0) }
        upcoming = tracks.dropFirst().map { QueueItem(track: $0) }
        self.mood = mood
        sentAhead = 0
    }

    public mutating func markSent() { sentAhead = min(upcoming.count, Self.maxSent) }

    // MARK: Edits

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { upcoming[$0] }
        var rest = upcoming.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        upcoming = rest
    }

    public mutating func remove(_ id: UUID) {
        upcoming.removeAll { $0.id == id }
    }

    public mutating func playNext(_ track: Track) {
        upcoming.insert(QueueItem(track: track, addedByYou: true), at: 0)
    }

    public mutating func addToEnd(_ track: Track) {
        upcoming.append(QueueItem(track: track, addedByYou: true))
    }

    /// Skips straight to a queued song.
    @discardableResult
    public mutating func jump(to id: UUID) -> Bool {
        guard let current, let index = upcoming.firstIndex(where: { $0.id == id }) else { return false }
        history.append(current)
        history += upcoming[..<index]
        self.current = upcoming[index]
        upcoming.removeFirst(index + 1)
        sentAhead = 0
        return true
    }

    /// Keeps the queue going in its mood.
    public mutating func extend(with tracks: [Track]) {
        upcoming += tracks.map { QueueItem(track: $0) }
    }

    // MARK: Following Spotify

    /// Moves the queue to whatever Spotify is playing. Returns false if that song isn't part of the queue
    /// (you started something else in Spotify), in which case MoodMix stops steering playback.
    public mutating func follow(playingTrackID id: String) -> Bool {
        guard let current else { return false }
        if id == current.track.id { return true }

        // Skipped forward (or the song ended).
        if let index = upcoming.firstIndex(where: { $0.track.id == id }) {
            history.append(current)
            history += upcoming[..<index]
            self.current = upcoming[index]
            upcoming.removeFirst(index + 1)
            sentAhead = max(0, sentAhead - (index + 1))
            return true
        }

        // Went back with "previous".
        if let index = history.lastIndex(where: { $0.track.id == id }) {
            let returning = Array(history[(index + 1)...]) + [current]
            self.current = history[index]
            history.removeSubrange(index...)
            upcoming.insert(contentsOf: returning, at: 0)
            sentAhead += returning.count
            return true
        }
        return false
    }
}
