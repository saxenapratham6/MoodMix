@testable import MoodMixCore
import XCTest

final class LabelArchiveTests: XCTestCase {
    func testRoundTripKeepsMoodsFeaturesAndLearning() {
        var p = TrackProfile(features: AudioFeatures(energy: 0.42, valence: 0.17, danceability: 0.5, acousticness: 0.8,
                                                     instrumentalness: 0.01, tempo: 92.4, key: 9, mode: 0),
                             featureSource: .reccobeats, moods: [.sad, .chill], genre: "indie")
        p.feedback = ["sad": 0.1]
        let unlabeled = TrackProfile(features: AudioFeatures(energy: 0.5, valence: 0.5, tempo: 100, key: 1, mode: 1))
        let data = LabelArchive.encode(["a": p, "b": unlabeled])
        let back = LabelArchive.decode(data)

        XCTAssertNil(back["b"], "songs without moods aren't worth backing up")
        let r = back["a"]!
        XCTAssertEqual(r.moods, [.sad, .chill])
        XCTAssertEqual(r.genre, "indie")
        XCTAssertEqual(r.featureSource, .reccobeats)
        XCTAssertEqual(r.features!.energy, 0.42, accuracy: 0.005)
        XCTAssertEqual(r.features!.tempo, 92, accuracy: 0.5)
        XCTAssertEqual(r.features!.key, 9)
        XCTAssertEqual(r.feedback?["sad"], 0.1)
    }

    func testAThousandSongsStaySmall() {
        let moods = Mood.allCases
        var profiles: [String: TrackProfile] = [:]
        for i in 0..<1050 {
            let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(22))
            profiles[id] = TrackProfile(features: AudioFeatures(energy: Double(i % 100) / 100, valence: 0.5, tempo: 120, key: i % 12, mode: i % 2),
                                        featureSource: .reccobeats, moods: [moods[i % 8], moods[(i + 3) % 8]])
        }
        let size = LabelArchive.encode(profiles).count
        XCTAssertLessThan(size, 80_000, "\(size) bytes")
        XCTAssertEqual(LabelArchive.decode(LabelArchive.encode(profiles)).count, 1050)
    }
}
