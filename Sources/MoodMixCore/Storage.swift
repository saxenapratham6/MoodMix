import Foundation
import Security

/// Tiny Keychain wrapper for tokens and API keys.
public enum Keychain {
    static let service = "MoodMix"

    public static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// On-disk cache of track profiles so each song is analyzed only once.
public actor ProfileStore {
    private var profiles: [String: TrackProfile] = [:]
    private let url: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoodMix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("profiles.json")
        if let data = try? Data(contentsOf: url) {
            profiles = (try? JSONDecoder().decode([String: TrackProfile].self, from: data)) ?? [:]
        }
    }

    public func all() -> [String: TrackProfile] { profiles }

    public func update(_ changes: [String: TrackProfile]) {
        profiles.merge(changes) { _, new in new }
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Playlists, their songs and favorite scores, saved so launching MoodMix doesn't re-download
/// a whole library (Spotify's Dev Mode quota is small). A playlist's songs are re-fetched only
/// when its snapshot ID changes.
public struct LibrarySnapshot: Codable, Sendable {
    public struct CachedPlaylist: Codable, Sendable {
        public var snapshotID: String?
        public var tracks: [Track]
    }

    public var playlists: [Playlist] = []
    public var tracks: [String: CachedPlaylist] = [:]
    public var favorites: FavoriteSignals?
    public var favoritesFetchedAt: Date?
}

public actor LibraryCache {
    private let url: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoodMix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("library.json")
    }

    public func load() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: url) else { return LibrarySnapshot() }
        return (try? JSONDecoder().decode(LibrarySnapshot.self, from: data)) ?? LibrarySnapshot()
    }

    public func save(_ snapshot: LibrarySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}

/// A plain-text record of the playback commands MoodMix sends, in ~/Library/Logs/MoodMix.log,
/// so surprises ("why did it pause?") can be traced afterwards.
public enum ActivityLog {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/MoodMix.log")
    private static let queue = DispatchQueue(label: "MoodMix.ActivityLog")

    public static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            // Keep it small: start over past 1 MB.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

extension Keychain {
    public static func setData(_ data: Data?, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let data, !data.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        // Readable without the phone being unlocked first, and never synced elsewhere.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func getData(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

/// Every song's mood labels and audio data, packed small (about 30 bytes a song, compressed).
/// Used for the iPhone's Keychain backup, which survives deleting the app, and for copying the
/// Mac's labels to the iPhone, so songs never have to be labeled by Claude twice.
public enum LabelArchive {
    private struct Entry: Codable {
        let i: String          // Spotify track ID
        let m: String          // moods as indices into Mood.allCases, strongest first
        var g: String?         // genre
        var f: [Int]?          // energy, valence, danceability, acousticness, instrumentalness ×100; tempo; key; mode
        var s: Int?            // 1 = measured (ReccoBeats), 0 = estimated (Claude)
        var u: Bool?           // you set the mood yourself
        var b: [String: Double]?  // what MoodMix learned from your skips and full plays
    }

    public static func encode(_ profiles: [String: TrackProfile]) -> Data {
        let entries = profiles.compactMap { id, p -> Entry? in
            guard !p.moods.isEmpty else { return nil }
            let moods = p.moods.compactMap { Mood.allCases.firstIndex(of: $0) }.map(String.init).joined()
            var entry = Entry(i: id, m: moods, g: p.genre)
            if let f = p.features {
                entry.f = [f.energy, f.valence, f.danceability, f.acousticness, f.instrumentalness].map { Int(($0 * 100).rounded()) }
                    + [Int(f.tempo.rounded()), f.key, f.mode]
                entry.s = p.featureSource == .reccobeats ? 1 : 0
            }
            entry.u = p.userTagged
            entry.b = p.feedback
            return entry
        }
        let json = (try? JSONEncoder().encode(entries)) ?? Data()
        return (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
    }

    public static func decode(_ data: Data) -> [String: TrackProfile] {
        let json = (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        guard let entries = try? JSONDecoder().decode([Entry].self, from: json) else { return [:] }
        var result: [String: TrackProfile] = [:]
        for e in entries {
            let moods = e.m.compactMap { Int(String($0)) }.filter { Mood.allCases.indices.contains($0) }.map { Mood.allCases[$0] }
            var profile = TrackProfile(moods: moods, genre: e.g)
            if let f = e.f, f.count == 8 {
                profile.features = AudioFeatures(energy: Double(f[0]) / 100, valence: Double(f[1]) / 100,
                                                 danceability: Double(f[2]) / 100, acousticness: Double(f[3]) / 100,
                                                 instrumentalness: Double(f[4]) / 100, tempo: Double(f[5]), key: f[6], mode: f[7])
                profile.featureSource = e.s == 1 ? .reccobeats : .claude
            }
            profile.userTagged = e.u
            profile.feedback = e.b
            result[e.i] = profile
        }
        return result
    }
}
