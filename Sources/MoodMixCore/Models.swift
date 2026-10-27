import Foundation

public struct Track: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let uri: String
    public let name: String
    public let artists: [String]
    public let album: String
    public let durationMs: Int
    public let addedAt: Date?
    public var artworkURL: URL?

    public init(id: String, uri: String, name: String, artists: [String], album: String, durationMs: Int, addedAt: Date?, artworkURL: URL? = nil) {
        self.id = id
        self.uri = uri
        self.name = name
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
        self.addedAt = addedAt
        self.artworkURL = artworkURL
    }

    public var artistLine: String { artists.joined(separator: ", ") }
}

public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let trackCount: Int
    public let imageURL: URL?
    public let snapshotID: String?
}

public struct NowPlaying: Hashable, Sendable {
    public let track: Track
    public let isPlaying: Bool
    public let progressMs: Int
    public let fetchedAt: Date
    /// The playlist/album/artist Spotify is playing from. MoodMix plays a plain list of songs,
    /// which has no context, so a non-nil value means you started this yourself in Spotify.
    public var contextURI: String? = nil
    /// The device's volume (0–100), when Spotify reports it.
    public var volumePercent: Int? = nil

    /// Progress extrapolated from the last poll, so the bar moves smoothly.
    public func progress(at date: Date) -> Int {
        guard isPlaying else { return progressMs }
        return min(track.durationMs, progressMs + Int(date.timeIntervalSince(fetchedAt) * 1000))
    }
}

/// Spotify-style audio features. 0...1 scales unless noted.
public struct AudioFeatures: Codable, Hashable, Sendable {
    public var energy: Double
    public var valence: Double
    public var danceability: Double
    public var acousticness: Double
    public var instrumentalness: Double
    /// Beats per minute.
    public var tempo: Double
    /// Pitch class 0 (C) ... 11 (B), or -1 when unknown.
    public var key: Int
    /// 1 = major, 0 = minor.
    public var mode: Int

    public init(energy: Double, valence: Double, danceability: Double = 0.5, acousticness: Double = 0.3,
                instrumentalness: Double = 0, tempo: Double, key: Int, mode: Int) {
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.acousticness = acousticness
        self.instrumentalness = instrumentalness
        self.tempo = tempo
        self.key = key
        self.mode = mode
    }
}

public enum FeatureSource: String, Codable, Sendable {
    case reccobeats   // measured audio analysis
    case claude       // estimated by Claude from title/artist
}

/// Everything MoodMix knows about one track, cached on disk.
public struct TrackProfile: Codable, Hashable, Sendable {
    public var features: AudioFeatures?
    public var featureSource: FeatureSource?
    /// Mood labels from Claude, strongest first.
    public var moods: [Mood]
    public var genre: String?
    /// Learned from listening: mood raw value → adjustment (skips lower it, full listens raise it).
    public var feedback: [String: Double]?
    /// You set this song's mood yourself, so analysis never overwrites it.
    public var userTagged: Bool?

    public init(features: AudioFeatures? = nil, featureSource: FeatureSource? = nil, moods: [Mood] = [], genre: String? = nil) {
        self.features = features
        self.featureSource = featureSource
        self.moods = moods
        self.genre = genre
    }
}

public enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case chill, happy, energetic, focus, sad, romantic, party, workout

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public var symbol: String {
        switch self {
        case .chill: "cloud.sun"
        case .happy: "sun.max"
        case .energetic: "bolt"
        case .focus: "brain.head.profile"
        case .sad: "cloud.rain"
        case .romantic: "heart"
        case .party: "party.popper"
        case .workout: "figure.run"
        }
    }

    /// Target ranges used to score measured/estimated audio features.
    struct Target {
        var energy: ClosedRange<Double>
        var valence: ClosedRange<Double>
        var tempo: ClosedRange<Double>? = nil
        var danceability: ClosedRange<Double>? = nil
        var prefersAcoustic = false
        var prefersInstrumental = false
    }

    var target: Target {
        switch self {
        case .chill: Target(energy: 0.15...0.5, valence: 0.3...0.75, tempo: 60...110)
        case .happy: Target(energy: 0.5...0.85, valence: 0.65...1)
        case .energetic: Target(energy: 0.7...1, valence: 0.4...1, tempo: 110...180)
        case .focus: Target(energy: 0.2...0.55, valence: 0.2...0.7, prefersInstrumental: true)
        case .sad: Target(energy: 0.05...0.5, valence: 0...0.35)
        case .romantic: Target(energy: 0.2...0.6, valence: 0.4...0.8, prefersAcoustic: true)
        case .party: Target(energy: 0.7...1, valence: 0.5...1, danceability: 0.65...1)
        case .workout: Target(energy: 0.75...1, valence: 0.3...1, tempo: 120...180)
        }
    }
}

/// How the energy should move across the mix.
public enum EnergyArc: String, CaseIterable, Identifiable, Sendable {
    case steady, buildUp, windDown, peak

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .steady: "Steady"
        case .buildUp: "Build up"
        case .windDown: "Wind down"
        case .peak: "Peak in the middle"
        }
    }

    /// Relative energy (0...1) wanted at position `t` (0...1) through the mix.
    func level(at t: Double) -> Double {
        switch self {
        case .steady: 0.5
        case .buildUp: t
        case .windDown: 1 - t
        case .peak: 1 - abs(2 * t - 1)
        }
    }
}
