@testable import MoodMixCore
import XCTest

final class MixBuilderTests: XCTestCase {
    func testCamelot() {
        XCTAssertEqual(MixBuilder.camelot(key: 0, mode: 1)?.description, "8B")  // C major
        XCTAssertEqual(MixBuilder.camelot(key: 9, mode: 0)?.description, "8A")  // A minor
        XCTAssertEqual(MixBuilder.camelot(key: 7, mode: 1)?.description, "9B")  // G major
        XCTAssertNil(MixBuilder.camelot(key: -1, mode: 1))
    }

    func testTempoAllowsDoubleTime() {
        let a = AudioFeatures(energy: 0.5, valence: 0.5, tempo: 70, key: 0, mode: 1)
        let b = AudioFeatures(energy: 0.5, valence: 0.5, tempo: 140, key: 0, mode: 1)
        XCTAssertEqual(MixBuilder.tempoScore(a, b), 1, accuracy: 0.001)
    }

    func testOnlyPlaylistTracksMatchingMoodArePicked() {
        var tracks: [Track] = []
        var profiles: [String: TrackProfile] = [:]
        for i in 0..<40 {
            let sad = i < 20
            let t = Track(id: "t\(i)", uri: "spotify:track:t\(i)", name: "Song \(i)", artists: ["Artist \(i)"],
                          album: "", durationMs: 180_000, addedAt: nil)
            tracks.append(t)
            profiles[t.id] = TrackProfile(
                features: AudioFeatures(energy: sad ? 0.25 : 0.9, valence: sad ? 0.15 : 0.8, tempo: sad ? 80 : 128, key: i % 12, mode: 1),
                featureSource: .reccobeats,
                moods: [sad ? .sad : .party])
        }
        let mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: FavoriteSignals(),
                                   request: MixRequest(mood: .sad, minutes: 30, seed: 1))
        XCTAssertEqual(mix.count, 10)
        XCTAssertTrue(mix.allSatisfy { Int($0.track.id.dropFirst())! < 20 })
        XCTAssertEqual(Set(mix.map(\.id)).count, mix.count)
    }

    func testFavoritesWinWhenWeighted() {
        let tracks = (0..<30).map { Track(id: "t\($0)", uri: "u\($0)", name: "\($0)", artists: ["a\($0)"], album: "", durationMs: 200_000, addedAt: nil) }
        let profiles = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, TrackProfile(moods: [.chill])) })
        let favorites = FavoriteSignals(scores: ["t29": 1, "t28": 1])
        let mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: favorites,
                                   request: MixRequest(mood: .chill, minutes: 10, favoriteWeight: 0.9, seed: 7))
        XCTAssertTrue(mix.contains { $0.id == "t29" })
        XCTAssertTrue(mix.contains { $0.id == "t28" })
    }

    func testBuildUpArcRisesInEnergy() {
        let tracks = (0..<12).map { Track(id: "t\($0)", uri: "u\($0)", name: "\($0)", artists: ["a\($0)"], album: "", durationMs: 200_000, addedAt: nil) }
        let profiles = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { i, t in
            (t.id, TrackProfile(features: AudioFeatures(energy: 0.7 + Double(i % 6) * 0.05, valence: 0.7, tempo: 125, key: 0, mode: 1),
                                featureSource: .reccobeats, moods: [.energetic]))
        })
        let mix = MixBuilder.build(tracks: tracks, profiles: profiles, favorites: FavoriteSignals(),
                                   request: MixRequest(mood: .energetic, minutes: 40, arc: .buildUp, seed: 3))
        let energies = mix.compactMap { $0.profile?.features?.energy }
        XCTAssertLessThan(energies.prefix(3).reduce(0, +), energies.suffix(3).reduce(0, +))
    }
}
