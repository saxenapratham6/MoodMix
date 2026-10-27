@testable import MoodMixCore
import XCTest

final class ExportTests: XCTestCase {
    func testCSVHasTransferToolColumnsAndQuotesCommas() throws {
        let track = Track(id: "abc", uri: "spotify:track:abc", name: "Dildaara (Stand By Me)",
                          artists: ["Vishal-Shekhar", "Shafqat Amanat Ali"], album: "Ra.One", durationMs: 300_000,
                          addedAt: nil, isrc: "INS181100123")
        let profiles = ["abc": TrackProfile(features: AudioFeatures(energy: 0.4, valence: 0.6, tempo: 92, key: 9, mode: 0),
                                            moods: [.romantic, .chill])]
        let playlist = PlaylistExport.playlist(name: "Prathman's OP Playlist", id: "p1", tracks: [track], profiles: profiles)
        let lines = PlaylistExport.csv([playlist]).split(separator: "\n")
        XCTAssertEqual(lines[0], "Track name,Artist name,Album,Playlist name,Type,ISRC,Spotify URL,Moods")
        XCTAssertEqual(lines[1], "Dildaara (Stand By Me),\"Vishal-Shekhar, Shafqat Amanat Ali\",Ra.One,Prathman's OP Playlist,Playlist,INS181100123,https://open.spotify.com/track/abc,romantic chill")

        let decoded = try JSONDecoder().decode([PlaylistExport.Playlist].self, from: PlaylistExport.json([playlist]))
        XCTAssertEqual(decoded[0].songs[0].camelotKey, "8A")
        XCTAssertEqual(decoded[0].songs[0].bpm, 92)
    }
}
