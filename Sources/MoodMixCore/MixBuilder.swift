import Foundation

/// How much the listener loves a track, from Spotify's top-tracks and Liked Songs.
public struct FavoriteSignals: Codable, Sendable {
    /// Spotify track ID -> 0...1 (1 = most played recently).
    public var scores: [String: Double]

    public init(scores: [String: Double] = [:]) { self.scores = scores }

    public func score(for id: String) -> Double { scores[id] ?? 0 }
}

public struct MixRequest: Sendable {
    public var mood: Mood
    public var minutes: Int
    /// 0 = ignore favorites, 1 = favorites dominate.
    public var favoriteWeight: Double
    public var arc: EnergyArc
    /// Different seeds give different (but equally on-mood) mixes.
    public var seed: UInt64
    /// When set, the mix starts from this track (used by "Match" to continue from the current song).
    public var startTrackID: String?

    public init(mood: Mood, minutes: Int = 60, favoriteWeight: Double = 0.4, arc: EnergyArc = .steady,
                seed: UInt64 = .random(in: 0...UInt64.max), startTrackID: String? = nil) {
        self.startTrackID = startTrackID
        self.mood = mood
        self.minutes = minutes
        self.favoriteWeight = favoriteWeight
        self.arc = arc
        self.seed = seed
    }
}

public struct MixEntry: Identifiable, Hashable, Sendable {
    public var id: String { track.id }
    public let track: Track
    public let profile: TrackProfile?
    public let moodScore: Double
    public let favoriteScore: Double
    /// How well this track flows from the previous one (nil for the first track).
    public let transition: Transition?
}

public struct Transition: Hashable, Sendable {
    public let score: Double
    public let harmonic: Double
    public let tempo: Double

    public var label: String {
        switch score {
        case 0.75...: "Smooth"
        case 0.5..<0.75: "OK"
        default: "Jump"
        }
    }
}

public enum MixBuilder {
    // MARK: Mood scoring

    /// 0...1 fit between a track and a mood, from Claude's labels and/or audio features.
    public static func moodScore(_ profile: TrackProfile?, mood: Mood) -> Double {
        guard let profile else { return 0 }
        let base = baseMoodScore(profile, mood: mood)
        guard base > 0, let adjustment = profile.feedback?[mood.rawValue] else { return base }
        return min(max(base + adjustment, 0), 1)
    }

    static func baseMoodScore(_ profile: TrackProfile, mood: Mood) -> Double {
        var tagScore: Double?
        if !profile.moods.isEmpty {
            if let i = profile.moods.firstIndex(of: mood) {
                tagScore = [1.0, 0.8, 0.6][min(i, 2)]
            } else {
                tagScore = 0
            }
        }
        let featureScore = profile.features.map { featureFit($0, mood.target) }

        switch (tagScore, featureScore) {
        case let (t?, f?):
            // Measured audio data deserves more weight than Claude's estimate of the same numbers.
            let fw = profile.featureSource == .reccobeats ? 0.45 : 0.3
            return t * (1 - fw) + f * fw
        case let (t?, nil): return t
        case let (nil, f?): return f
        default: return 0
        }
    }

    static func featureFit(_ f: AudioFeatures, _ t: Mood.Target) -> Double {
        var parts = [fit(f.energy, t.energy, slack: 0.25), fit(f.valence, t.valence, slack: 0.25)]
        if let tempo = t.tempo { parts.append(fit(f.tempo, tempo, slack: 30)) }
        if let dance = t.danceability { parts.append(fit(f.danceability, dance, slack: 0.25)) }
        var score = parts.reduce(0, +) / Double(parts.count)
        if t.prefersAcoustic { score = score * 0.8 + f.acousticness * 0.2 }
        if t.prefersInstrumental { score = score * 0.75 + f.instrumentalness * 0.25 }
        return score
    }

    /// 1 inside the range, falling linearly to 0 at `slack` outside it.
    static func fit(_ value: Double, _ range: ClosedRange<Double>, slack: Double) -> Double {
        if range.contains(value) { return 1 }
        let distance = value < range.lowerBound ? range.lowerBound - value : value - range.upperBound
        return max(0, 1 - distance / slack)
    }

    // MARK: Harmonic mixing

    /// Camelot wheel position: number 1...12, `minor` = "A", major = "B".
    public struct Camelot: Hashable, Sendable, CustomStringConvertible {
        public let number: Int
        public let minor: Bool
        public var description: String { "\(number)\(minor ? "A" : "B")" }
    }

    public static func camelot(key: Int, mode: Int) -> Camelot? {
        guard (0...11).contains(key) else { return nil }
        // Pitch class -> Camelot number (major: C = 8B; minor: A = 8A).
        let major = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
        let minor = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]
        return mode == 1 ? Camelot(number: major[key], minor: false) : Camelot(number: minor[key], minor: true)
    }

    static func harmonicScore(_ a: AudioFeatures?, _ b: AudioFeatures?) -> Double {
        guard let a, let b, let ca = camelot(key: a.key, mode: a.mode), let cb = camelot(key: b.key, mode: b.mode) else {
            return 0.6
        }
        let diff = (ca.number - cb.number + 12) % 12
        let step = min(diff, 12 - diff)
        switch (step, ca.minor == cb.minor) {
        case (0, true): return 1
        case (1, true): return 0.9
        case (0, false): return 0.85
        case (2, true): return 0.5
        case (1, false): return 0.45
        default: return 0.2
        }
    }

    static func tempoScore(_ a: AudioFeatures?, _ b: AudioFeatures?) -> Double {
        guard let a, let b, a.tempo > 0, b.tempo > 0 else { return 0.6 }
        // Half/double time mixes fine, so compare against the closest of the three.
        let diff = [b.tempo, b.tempo * 2, b.tempo / 2].map { abs(a.tempo - $0) / a.tempo }.min()!
        return max(0, 1 - diff / 0.12)
    }

    static func transition(from a: TrackProfile?, to b: TrackProfile?) -> Transition {
        let h = harmonicScore(a?.features, b?.features)
        let t = tempoScore(a?.features, b?.features)
        return Transition(score: 0.55 * h + 0.45 * t, harmonic: h, tempo: t)
    }

    // MARK: Building a mix

    public static func build(tracks: [Track], profiles: [String: TrackProfile], favorites: FavoriteSignals, request: MixRequest) -> [MixEntry] {
        var rng = SeededGenerator(seed: request.seed)
        let w = min(max(request.favoriteWeight, 0), 1)

        struct Candidate { let track: Track; let mood: Double; let fav: Double; let rank: Double }
        let scored = tracks.map { track -> Candidate in
            let m = moodScore(profiles[track.id], mood: request.mood)
            let f = favorites.score(for: track.id)
            let jitter = Double.random(in: 0..<0.08, using: &rng)
            return Candidate(track: track, mood: m, fav: f, rank: m * (1 - w) + f * w + jitter)
        }

        // On-mood tracks only; loosen the bar if the playlist is thin for this mood.
        var pool = scored.filter { $0.mood >= 0.55 }
        if pool.count < 15 { pool = scored.filter { $0.mood >= 0.35 } }
        pool.sort { $0.rank > $1.rank }

        let budgetMs = request.minutes * 60_000
        var picked: [Candidate] = []
        var total = 0
        for c in pool where total < budgetMs {
            picked.append(c)
            total += c.track.durationMs
        }
        if let startID = request.startTrackID, let start = scored.first(where: { $0.track.id == startID }) {
            picked.removeAll { $0.track.id == startID }
            picked.insert(start, at: 0)
        }
        guard !picked.isEmpty else { return [] }

        // Order greedily for smooth transitions that follow the chosen energy arc.
        let energies = picked.compactMap { profiles[$0.track.id]?.features?.energy }
        let lo = energies.min() ?? 0.3, hi = energies.max() ?? 0.7
        func targetEnergy(_ position: Int) -> Double {
            let t = picked.count > 1 ? Double(position) / Double(picked.count - 1) : 0.5
            return lo + (hi - lo) * request.arc.level(at: t)
        }
        func energyFit(_ c: Candidate, _ position: Int) -> Double {
            guard let e = profiles[c.track.id]?.features?.energy else { return 0.5 }
            return max(0, 1 - abs(e - targetEnergy(position)) * 2.5)
        }

        var remaining = picked
        let firstIndex = request.startTrackID != nil && remaining[0].track.id == request.startTrackID ? 0 : remaining.indices.max {
            energyFit(remaining[$0], 0) + remaining[$0].fav * 0.3 < energyFit(remaining[$1], 0) + remaining[$1].fav * 0.3
        }!
        var ordered = [remaining.remove(at: firstIndex)]

        while !remaining.isEmpty {
            let prev = ordered.last!
            let position = ordered.count
            let bestIndex = remaining.indices.max { i, j in
                score(remaining[i]) < score(remaining[j])
            }!
            ordered.append(remaining.remove(at: bestIndex))

            func score(_ c: Candidate) -> Double {
                let t = transition(from: profiles[prev.track.id], to: profiles[c.track.id])
                let sameArtist = Set(prev.track.artists).isDisjoint(with: c.track.artists) ? 0 : 0.25
                return 0.45 * t.score + 0.35 * energyFit(c, position) + 0.2 * c.rank - sameArtist
            }
        }

        var result: [MixEntry] = []
        for (i, c) in ordered.enumerated() {
            let t = i == 0 ? nil : transition(from: profiles[ordered[i - 1].track.id], to: profiles[c.track.id])
            result.append(MixEntry(track: c.track, profile: profiles[c.track.id], moodScore: c.mood, favoriteScore: c.fav, transition: t))
        }
        return result
    }
}

/// SplitMix64, so a mix can be reproduced from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
