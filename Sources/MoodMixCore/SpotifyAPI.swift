import Foundation

/// The slice of the Spotify Web API MoodMix needs (Dev Mode rules as of 2026).
public struct SpotifyAPI: Sendable {
    let auth: SpotifyAuth
    let base = URL(string: "https://api.spotify.com/v1/")!

    public init(auth: SpotifyAuth) { self.auth = auth }

    // MARK: Library

    public func myPlaylists() async throws -> [Playlist] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Count: Decodable { let total: Int }
                let id: String
                let name: String
                let items: Count?   // 2026 name
                let tracks: Count?  // legacy name
            }
            let items: [Item?]
            let next: String?
        }
        var result: [Playlist] = []
        var url: URL? = endpoint("me/playlists", ["limit": "50"])
        while let u = url {
            let page: Page = try await get(u)
            result += page.items.compactMap { $0 }.map {
                Playlist(id: $0.id, name: $0.name, trackCount: $0.items?.total ?? $0.tracks?.total ?? 0)
            }
            url = page.next.flatMap(URL.init(string:))
        }
        return result
    }

    /// All playable tracks in a playlist you own or collaborate on.
    public func tracks(inPlaylist id: String, progress: (@Sendable (Int) -> Void)? = nil) async throws -> [Track] {
        struct Page: Decodable { let items: [PlaylistItem]; let next: String? }
        var result: [Track] = []
        var url: URL? = endpoint("playlists/\(id)/items", ["limit": "50"])
        while let u = url {
            let page: Page = try await get(u)
            result += page.items.compactMap { $0.asTrack }
            progress?(result.count)
            url = page.next.flatMap(URL.init(string:))
        }
        // A playlist can contain the same song twice; keep the first.
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    /// Favorite scores from top tracks (short/medium/long term) and Liked Songs.
    public func favoriteSignals(likedLimit: Int = 1000) async throws -> FavoriteSignals {
        struct TopPage: Decodable { let items: [TrackObject] }
        var scores: [String: Double] = [:]
        for (range, weight) in [("short_term", 1.0), ("medium_term", 0.85), ("long_term", 0.7)] {
            for offset in [0, 49] {
                let page: TopPage = try await get(endpoint("me/top/tracks", ["time_range": range, "limit": "50", "offset": "\(offset)"]))
                for (i, t) in page.items.enumerated() {
                    guard let id = t.id else { continue }
                    let s = weight * (1 - Double(offset + i) / 200)
                    scores[id] = max(scores[id] ?? 0, s)
                }
            }
        }
        struct SavedPage: Decodable { let items: [PlaylistItem]; let next: String? }
        var url: URL? = endpoint("me/tracks", ["limit": "50"])
        var count = 0
        while let u = url, count < likedLimit {
            let page: SavedPage = try await get(u)
            for item in page.items { if let id = item.asTrack?.id { scores[id] = max(scores[id] ?? 0, 0.45) } }
            count += page.items.count
            url = page.next.flatMap(URL.init(string:))
        }
        return FavoriteSignals(scores: scores)
    }

    // MARK: Playback

    public struct Device: Decodable, Sendable {
        public let id: String?
        public let name: String
        public let type: String
        public let is_active: Bool
    }

    public func devices() async throws -> [Device] {
        struct R: Decodable { let devices: [Device] }
        let r: R = try await get(endpoint("me/player/devices"))
        return r.devices
    }

    /// Plays exactly these tracks, in this order, on the active (or first available) device.
    public func play(uris: [String]) async throws {
        let devices = try await devices()
        guard let device = devices.first(where: \.is_active) ?? devices.first(where: { $0.type == "Computer" }) ?? devices.first,
              let deviceID = device.id else { throw SpotifyError.noActiveDevice }
        try await send("PUT", endpoint("me/player/shuffle", ["state": "false", "device_id": deviceID]))
        let body = try JSONSerialization.data(withJSONObject: ["uris": Array(uris.prefix(100))])
        try await send("PUT", endpoint("me/player/play", ["device_id": deviceID]), body: body)
    }

    // MARK: Plumbing

    func endpoint(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }

    func get<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await send("GET", url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func send(_ method: String, _ url: URL, body: Data? = nil, attempt: Int = 0) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200..<300:
            return data
        case 429 where attempt < 4:
            let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)
            try await Task.sleep(for: .seconds(min(wait, 30)))
            return try await send(method, url, body: body, attempt: attempt + 1)
        case 404 where url.path.contains("/me/player"):
            throw SpotifyError.noActiveDevice
        default:
            throw SpotifyError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}

struct TrackObject: Decodable {
    struct Name: Decodable { let name: String }
    let id: String?
    let uri: String?
    let name: String?
    let type: String?
    let is_local: Bool?
    let duration_ms: Int?
    let artists: [Name]?
    let album: Name?
}

/// A playlist or Liked Songs entry. Spotify renamed `track` to `item` in 2026; accept both.
struct PlaylistItem: Decodable {
    let added_at: String?
    let item: TrackObject?
    let track: TrackObject?

    var asTrack: Track? {
        guard let t = item ?? track, t.type ?? "track" == "track", t.is_local != true,
              let id = t.id, let uri = t.uri, let name = t.name else { return nil }
        return Track(id: id, uri: uri, name: name,
                     artists: t.artists?.map(\.name) ?? [],
                     album: t.album?.name ?? "",
                     durationMs: t.duration_ms ?? 210_000,
                     addedAt: added_at.flatMap { ISO8601DateFormatter().date(from: $0) })
    }
}
