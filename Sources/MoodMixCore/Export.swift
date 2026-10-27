import Foundation

/// Playlists written out for moving to another service. The CSV uses the columns transfer tools
/// such as TuneMyMusic and Soundiiz import; the JSON keeps everything MoodMix knows (moods, tempo, key).
public enum PlaylistExport {
    public struct Song: Codable, Sendable {
        public let name: String
        public let artists: [String]
        public let album: String
        public let isrc: String?
        public let spotifyURI: String
        public let spotifyURL: String
        public let durationSeconds: Int
        public let moods: [String]
        public let bpm: Int?
        public let camelotKey: String?
    }

    public struct Playlist: Codable, Sendable {
        public let name: String
        public let spotifyID: String
        public let songs: [Song]
    }

    public static func playlist(name: String, id: String, tracks: [Track], profiles: [String: TrackProfile]) -> Playlist {
        Playlist(name: name, spotifyID: id, songs: tracks.map { track in
            let profile = profiles[track.id]
            let features = profile?.features
            return Song(name: track.name, artists: track.artists, album: track.album, isrc: track.isrc,
                        spotifyURI: track.uri, spotifyURL: "https://open.spotify.com/track/\(track.id)",
                        durationSeconds: track.durationMs / 1000,
                        moods: profile?.moods.map(\.rawValue) ?? [],
                        bpm: features.map { Int($0.tempo.rounded()) },
                        camelotKey: features.flatMap { MixBuilder.camelot(key: $0.key, mode: $0.mode)?.description })
        })
    }

    public static func csv(_ playlists: [Playlist]) -> String {
        var lines = ["Track name,Artist name,Album,Playlist name,Type,ISRC,Spotify URL,Moods"]
        for playlist in playlists {
            for song in playlist.songs {
                lines.append([song.name, song.artists.joined(separator: ", "), song.album, playlist.name, "Playlist",
                              song.isrc ?? "", song.spotifyURL, song.moods.joined(separator: " ")]
                    .map(field).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func json(_ playlists: [Playlist]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(playlists)
    }

    /// Quotes a CSV field when it contains a comma, quote or newline.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
