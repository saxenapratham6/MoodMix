@testable import MoodMixCore
import XCTest

final class DiscoveryTests: XCTestCase {
    private func card(_ id: String, mood: Mood? = .chill) -> DiscoveryCard {
        DiscoveryCard(track: Track(id: id, uri: "spotify:track:\(id)", name: id, artists: ["A"], album: "", durationMs: 200_000, addedAt: nil),
                      reason: "test", features: nil, mood: mood, popularity: nil)
    }

    func testCountsKeepsAndRemembersSeen() {
        var stats = DiscoveryStats()
        stats.record(.add, card: card("a", mood: .sad))
        stats.record(.next, card: card("b", mood: .sad))
        stats.record(.skip, card: card("c"))
        XCTAssertEqual(stats.explored, 3)
        XCTAssertEqual(stats.kept, 2)
        XCTAssertEqual(stats.keepRate, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stats.keptMoods["sad"], 2)
        XCTAssertEqual(stats.recentFinds.map(\.id), ["b", "a"])
        XCTAssertEqual(Set(stats.seen), ["a", "b", "c"])
    }

    func testStreakCountsConsecutiveDays() {
        var stats = DiscoveryStats()
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        for daysAgo in [3, 2, 1, 0] {
            stats.record(.skip, card: card("s\(daysAgo)"), on: today.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        XCTAssertEqual(stats.streak(today: today), 4)
        // Not swiped yet today: yesterday's streak still counts.
        XCTAssertEqual(stats.streak(today: today.addingTimeInterval(86_400)), 4)
        // A missed day breaks it.
        XCTAssertEqual(stats.streak(today: today.addingTimeInterval(2 * 86_400)), 0)
    }

    func testBestMoodFromAudio() {
        let sad = AudioFeatures(energy: 0.2, valence: 0.1, tempo: 70, key: 0, mode: 0)
        let party = AudioFeatures(energy: 0.9, valence: 0.85, danceability: 0.85, tempo: 124, key: 5, mode: 1)
        XCTAssertEqual(MixBuilder.bestMood(for: sad), .sad)
        XCTAssertTrue([.party, .happy, .energetic].contains(MixBuilder.bestMood(for: party)))
    }
}
