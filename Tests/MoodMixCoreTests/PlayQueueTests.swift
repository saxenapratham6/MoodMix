@testable import MoodMixCore
import XCTest

final class PlayQueueTests: XCTestCase {
    private func track(_ n: Int) -> Track {
        Track(id: "t\(n)", uri: "spotify:track:t\(n)", name: "Song \(n)", artists: ["A\(n)"], album: "", durationMs: 200_000, addedAt: nil)
    }

    private func started(_ count: Int = 5) -> PlayQueue {
        var q = PlayQueue()
        q.start((0..<count).map(track), mood: .sad)
        q.markSent()
        return q
    }

    func testStartSendsCurrentFirst() {
        let q = started()
        XCTAssertEqual(q.current?.track.id, "t0")
        XCTAssertEqual(q.uris.first, "spotify:track:t0")
        XCTAssertEqual(q.uris.count, 5)
        XCTAssertEqual(q.sentAhead, 4)
    }

    func testFollowsSongEndingAndSkips() {
        var q = started()
        XCTAssertTrue(q.follow(playingTrackID: "t1"))
        XCTAssertEqual(q.current?.track.id, "t1")
        XCTAssertTrue(q.follow(playingTrackID: "t3"))  // skipped t2
        XCTAssertEqual(q.current?.track.id, "t3")
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t4"])
        XCTAssertEqual(q.history.map(\.track.id), ["t0", "t1", "t2"])
        XCTAssertEqual(q.sentAhead, 1)
    }

    func testPreviousPutsSongsBack() {
        var q = started()
        _ = q.follow(playingTrackID: "t2")
        XCTAssertTrue(q.follow(playingTrackID: "t1"))
        XCTAssertEqual(q.current?.track.id, "t1")
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t2", "t3", "t4"])
    }

    func testSomethingElseInSpotifyIsNotFollowed() {
        var q = started()
        XCTAssertFalse(q.follow(playingTrackID: "elsewhere"))
    }

    func testAddedSongPlaysThenMoodContinues() {
        var q = started()
        q.playNext(track(99))  // a happy song in a sad queue
        XCTAssertEqual(q.upcoming.first?.track.id, "t99")
        XCTAssertTrue(q.upcoming.first!.addedByYou)
        XCTAssertEqual(q.uris[1], "spotify:track:t99")
        _ = q.follow(playingTrackID: "t99")
        XCTAssertEqual(q.upcoming.first?.track.id, "t1")  // back to the sad songs
        XCTAssertEqual(q.mood, .sad)
    }

    func testMoveAndRemove() {
        var q = started()  // upcoming t1 t2 t3 t4
        q.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t4", "t1", "t2", "t3"])
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t1", "t2", "t3", "t4"])
        q.remove(q.upcoming[1].id)
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t1", "t3", "t4"])
    }

    func testRunningLowAsksForMoreAndResend() {
        var q = started(3)
        _ = q.follow(playingTrackID: "t2")
        XCTAssertTrue(q.needsMore)
        XCTAssertFalse(q.needsResend)
        q.extend(with: [track(7), track(8)])
        XCTAssertTrue(q.needsResend)  // Spotify only has t2; t7 and t8 must be sent
        q.markSent()
        XCTAssertFalse(q.needsResend)
    }

    func testJump() {
        var q = started()
        XCTAssertTrue(q.jump(to: q.upcoming[2].id))
        XCTAssertEqual(q.current?.track.id, "t3")
        XCTAssertEqual(q.upcoming.map(\.track.id), ["t4"])
    }
}
