import Foundation

/// One song in the Discover deck.
public struct DiscoveryCard: Identifiable, Hashable, Sendable {
    public var id: String { track.id }
    public var track: Track
    /// Why it's here, e.g. "Like Pyramid Song and Creep".
    public let reason: String
    public let features: AudioFeatures?
    /// Best-fitting mood from the measured audio (no Claude needed).
    public let mood: Mood?
    public let popularity: Int?
}

public enum SwipeAction: String, Codable, Sendable {
    case add   // right: add to the chosen playlist / the queue
    case next  // up: play right after the current song
    case skip  // left
}

/// What the deck's suggestions are based on.
public enum DiscoverSeed: Hashable, Sendable {
    case favorites
    case queue
    case mood(Mood)
    case song(Track)

    public var title: String {
        switch self {
        case .favorites: "Your favorites"
        case .queue: "Your queue"
        case .mood(let mood): "\(mood.title) songs"
        case .song(let track): track.name
        }
    }
}

/// Where a right swipe puts the song.
public enum DiscoverTarget: Hashable, Codable, Sendable {
    case queue
    case playlist(id: String, name: String)

    public var title: String {
        switch self {
        case .queue: "Your queue"
        case .playlist(_, let name): name
        }
    }
}

/// What you've explored, for the Profile tab. Saved on the device (and in the iPhone's Keychain backup).
public struct DiscoveryStats: Codable, Sendable {
    public var explored = 0
    public var added = 0
    public var queued = 0
    public var skipped = 0
    /// Moods of the songs you kept (added or queued).
    public var keptMoods: [String: Int] = [:]
    /// The latest songs you kept, newest first.
    public var recentFinds: [Track] = []
    /// Days you swiped, as yyyy-MM-dd.
    public var activeDays: [String] = []
    /// Songs already shown, so they don't come back.
    public var seen: [String] = []

    public init() {}

    public var kept: Int { added + queued }
    public var keepRate: Double { explored == 0 ? 0 : Double(kept) / Double(explored) }

    /// Consecutive days with swiping, ending today (or yesterday, if you haven't swiped yet today).
    public func streak(today: Date = Date()) -> Int {
        let days = Set(activeDays)
        var day = today
        if !days.contains(Self.key(day)) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(Self.key(day)) {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    mutating func record(_ action: SwipeAction, card: DiscoveryCard, on date: Date = Date()) {
        explored += 1
        switch action {
        case .add: added += 1
        case .next: queued += 1
        case .skip: skipped += 1
        }
        if action != .skip {
            if let mood = card.mood { keptMoods[mood.rawValue, default: 0] += 1 }
            recentFinds.removeAll { $0.id == card.id }
            recentFinds.insert(card.track, at: 0)
            recentFinds = Array(recentFinds.prefix(30))
        }
        let today = Self.key(date)
        if activeDays.last != today { activeDays.append(today) }
        activeDays = Array(activeDays.suffix(400))
        markSeen([card.id])
    }

    mutating func markSeen(_ ids: [String]) {
        seen.append(contentsOf: ids.filter { !seen.contains($0) })
        seen = Array(seen.suffix(3000))
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

extension MixBuilder {
    /// The mood whose audio profile fits these features best (used for discovered songs, which have no Claude label).
    public static func bestMood(for features: AudioFeatures) -> Mood {
        Mood.allCases.max { featureFit(features, $0.target) < featureFit(features, $1.target) } ?? .chill
    }
}
