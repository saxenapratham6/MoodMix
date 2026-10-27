import Foundation

// MARK: - Skip learning

public enum ListeningOutcome: Sendable {
    case skipped, finished
}

extension TrackProfile {
    /// Skips push a song out of a mood a little; listening all the way through pulls it back in.
    mutating func learn(_ outcome: ListeningOutcome, mood: Mood) {
        var feedback = self.feedback ?? [:]
        let current = feedback[mood.rawValue] ?? 0
        switch outcome {
        case .skipped: feedback[mood.rawValue] = max(current - 0.15, -0.6)
        case .finished: feedback[mood.rawValue] = min(current + 0.05, 0.3)
        }
        self.feedback = feedback
    }
}

extension ListeningOutcome {
    /// Classifies how a song ended from how far into it playback got.
    static func judge(playedMs: Int, durationMs: Int) -> ListeningOutcome? {
        if playedMs < min(30_000, durationMs * 4 / 10) { return .skipped }
        if playedMs >= durationMs - 20_000 { return .finished }
        return nil  // somewhere in between: no signal
    }
}

// MARK: - Mood journeys

extension MixBuilder {
    /// A mix that moves through moods in order (e.g. sad → chill → happy), each section leading
    /// smoothly into the next.
    public static func buildJourney(_ moods: [Mood], tracks: [Track], profiles: [String: TrackProfile],
                                    favorites: FavoriteSignals, minutes: Int, favoriteWeight: Double,
                                    seed: UInt64 = .random(in: 0...UInt64.max)) -> [MixEntry] {
        guard !moods.isEmpty else { return [] }
        let perSection = max(10, minutes / moods.count)
        var result: [MixEntry] = []
        var used = Set<String>()
        for (i, mood) in moods.enumerated() {
            let anchor = result.last?.track
            let pool = tracks.filter { !used.contains($0.id) || $0.id == anchor?.id }
            // Energy eases toward the next section: build up into livelier moods, wind down into calmer ones.
            let arc: EnergyArc = {
                guard i + 1 < moods.count else { return .steady }
                return moods[i + 1].target.energy.lowerBound > mood.target.energy.lowerBound ? .buildUp : .windDown
            }()
            let request = MixRequest(mood: mood, minutes: perSection, favoriteWeight: favoriteWeight, arc: arc,
                                     seed: seed &+ UInt64(i), startTrackID: anchor?.id)
            var section = build(tracks: pool, profiles: profiles, favorites: favorites, request: request)
            if let anchor, section.first?.id == anchor.id { section.removeFirst() }
            result += section
            used.formUnion(section.map(\.id))
        }
        return result
    }
}

// MARK: - Mood from the moment

public struct MomentContext: Sendable {
    public var date: Date
    public var headphones: Bool

    public init(date: Date = Date(), headphones: Bool = false) {
        self.date = date
        self.headphones = headphones
    }

    var hour: Int { Calendar.current.component(.hour, from: date) }
    var weekday: Int { Calendar.current.component(.weekday, from: date) }  // 1 = Sunday
    var isWeekend: Bool { weekday == 1 || weekday == 7 }
    var isPartyNight: Bool { (weekday == 6 || weekday == 7) && hour >= 20 }  // Fri/Sat evening
}

/// A mood you picked, remembered so suggestions learn your habits.
public struct MoodPick: Codable, Sendable {
    public let date: Date
    public let mood: Mood
}

public enum MoodSuggester {
    public struct Suggestion: Sendable {
        public let mood: Mood
        public let reason: String
    }

    public static func suggest(for context: MomentContext, history: [MoodPick]) -> Suggestion {
        var scores = prior(for: context)

        // Your own habits around this time of day (and same weekday/weekend) count most.
        var habit: [Mood: Double] = [:]
        for pick in history {
            let then = MomentContext(date: pick.date)
            let hourGap = min(abs(then.hour - context.hour), 24 - abs(then.hour - context.hour))
            guard hourGap <= 1, then.isWeekend == context.isWeekend else { continue }
            let ageDays = context.date.timeIntervalSince(pick.date) / 86_400
            guard ageDays >= 0, ageDays < 60 else { continue }
            habit[pick.mood, default: 0] += 1 / (1 + ageDays / 14)
        }
        let habitTotal = habit.values.reduce(0, +)
        if habitTotal > 0 {
            for (mood, weight) in habit { scores[mood, default: 0] += 1.5 * weight / habitTotal }
        }

        let best = scores.max { $0.value < $1.value }?.key ?? .chill
        let reason: String
        if let top = habit.max(by: { $0.value < $1.value }), top.key == best, habitTotal >= 2 {
            reason = "You usually pick \(best.title) around now"
        } else {
            reason = timeDescription(context) + (context.headphones ? " · headphones on" : "")
        }
        return Suggestion(mood: best, reason: reason)
    }

    static func prior(for c: MomentContext) -> [Mood: Double] {
        var s: [Mood: Double] = [:]
        switch c.hour {
        case 0..<5: s = [.chill: 0.8, .sad: 0.6, .romantic: 0.4]
        case 5..<9: s = [.happy: 0.7, .chill: 0.6, .workout: 0.5]
        case 9..<13: s = c.isWeekend ? [.happy: 0.7, .chill: 0.6] : [.focus: 0.9, .happy: 0.4]
        case 13..<17: s = c.isWeekend ? [.happy: 0.6, .energetic: 0.5, .party: 0.3] : [.focus: 0.7, .energetic: 0.5]
        case 17..<20: s = [.energetic: 0.6, .workout: 0.6, .happy: 0.5]
        case 20..<23: s = c.isPartyNight ? [.party: 0.8, .happy: 0.5] : [.chill: 0.6, .romantic: 0.5]
        default: s = [.chill: 0.7, .sad: 0.5]
        }
        if c.headphones && (6..<22).contains(c.hour) {
            for mood in [Mood.energetic, .workout, .focus] { s[mood, default: 0] += 0.2 }
        } else if !c.headphones {
            for mood in [Mood.chill, .party] { s[mood, default: 0] += 0.1 }
        }
        return s
    }

    static func timeDescription(_ c: MomentContext) -> String {
        let day = c.isWeekend ? "Weekend" : "Weekday"
        switch c.hour {
        case 0..<5: return "Late night"
        case 5..<12: return "\(day) morning"
        case 12..<17: return "\(day) afternoon"
        case 17..<21: return c.isPartyNight ? "Friday night" : "\(day) evening"
        default: return c.isPartyNight ? "Saturday night" : "Night"
        }
    }
}

// MARK: - Sleep timer

public enum SleepTimer: Equatable, Sendable {
    case off
    case endOfSong(trackID: String)
    case endOfMix(trackID: String)
    case at(Date)

    public var isOn: Bool { self != .off }
}
