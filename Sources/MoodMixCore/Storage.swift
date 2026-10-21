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
