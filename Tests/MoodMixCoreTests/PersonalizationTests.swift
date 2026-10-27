@testable import MoodMixCore
import XCTest

final class PersonalizationTests: XCTestCase {
    private func track(_ n: Int) -> Track {
        Track(id: "t\(n)", uri: "u\(n)", name: "\(n)", artists: ["a\(n)"], album: "", durationMs: 200_000, addedAt: nil)
    }

    func testSkipsLowerAndFullListensRaiseMoodFit() {
        var p = TrackProfile(moods: [.sad])
        let before = MixBuilder.moodScore(p, mood: .sad)
        p.learn(.skipped, mood: .sad)
        p.learn(.skipped, mood: .sad)
        XCTAssertLessThan(MixBuilder.moodScore(p, mood: .sad), before)
        for _ in 0..<20 { p.learn(.finished, mood: .sad) }
        XCTAssertEqual(p.feedback?["sad"] ?? 0, 0.3, accuracy: 0.001)  // capped
    }

    func testJudgingHowASongEnded() {
        XCTAssertEqual(ListeningOutcome.judge(playedMs: 10_000, durationMs: 200_000), .skipped)
        XCTAssertEqual(ListeningOutcome.judge(playedMs: 190_000, durationMs: 200_000), .finished)
        XCTAssertNil(ListeningOutcome.judge(playedMs: 100_000, durationMs: 200_000))
    }

    func testJourneyMovesThroughMoodsWithoutRepeats() {
        let tracks = (0..<60).map(track)
        var profiles: [String: TrackProfile] = [:]
        for (i, t) in tracks.enumerated() {
            let mood: Mood = i < 20 ? .sad : i < 40 ? .chill : .happy
            profiles[t.id] = TrackProfile(moods: [mood])
        }
        let mix = MixBuilder.buildJourney([.sad, .chill, .happy], tracks: tracks, profiles: profiles,
                                          favorites: FavoriteSignals(), minutes: 60, favoriteWeight: 0, seed: 4)
        let moods = mix.compactMap { profiles[$0.id]?.moods.first }
        XCTAssertEqual(moods.first, .sad)
        XCTAssertEqual(moods.last, .happy)
        XCTAssertEqual(Set(mix.map(\.id)).count, mix.count)
        // Sections stay in order.
        let firstHappy = moods.firstIndex(of: .happy)!, lastSad = moods.lastIndex(of: .sad)!
        XCTAssertLessThan(lastSad, firstHappy)
    }

    func testSuggestionLearnsHabits() {
        let calendar = Calendar.current
        let tuesdayNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 22))!
        let base = MoodSuggester.suggest(for: MomentContext(date: tuesdayNight), history: [])
        XCTAssertNotEqual(base.mood, .workout)
        let history = (1...5).map { MoodPick(date: tuesdayNight.addingTimeInterval(-Double($0) * 86_400), mood: .workout) }
        let learned = MoodSuggester.suggest(for: MomentContext(date: tuesdayNight), history: history)
        XCTAssertEqual(learned.mood, .workout)
        XCTAssertTrue(learned.reason.contains("usually"))
    }
}
