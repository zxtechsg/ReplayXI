import XCTest
@testable import ReplayXI

final class ReplayFootballShotTimeline130Tests: XCTestCase {
    private func player(_ id: String, team: FootballTeam, keeper: Bool = false) -> PlayerTrack {
        .init(id: id, displayName: id, role: keeper ? "GK" : "ST", shirtNumber: keeper ? 1 : 9,
              team: team, isGoalkeeper: keeper,
              keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                          .init(time: 10, position: .zero, facingDegrees: 0)])
    }

    private func touch(_ id: String, at time: Double,
                       kind: ReplayNativeBallPhysics.TouchKind = .shot) -> ReplayNativeBallPhysics.Touch {
        .init(time: time, playerID: id, position: [1, 0.7, 10], outgoingVelocity: [-2, 0.5, -14],
              kind: kind, kickingLeg: .left)
    }

    func testOnlyAlreadyObservedOpposingShotsCanDriveTheKeeper() throws {
        let h = player("h", team: .home), a = player("a", team: .away)
        let hk = player("hk", team: .home, keeper: true), ak = player("ak", team: .away, keeper: true)
        let timeline = ReplayFootballShotTimeline(touches: [touch("a", at: 7), touch("h", at: 3), touch("a", at: 5)],
                                                 players: [h, a, hk, ak])
        XCTAssertNil(timeline.latestOpposingShot(for: hk, at: 4.999))
        XCTAssertEqual(try XCTUnwrap(timeline.latestOpposingShot(for: hk, at: 5)).time, 5)
        XCTAssertEqual(try XCTUnwrap(timeline.latestOpposingShot(for: hk, at: 6.99)).time, 5)
        XCTAssertEqual(try XCTUnwrap(timeline.latestOpposingShot(for: hk, at: 7)).time, 7)
        XCTAssertEqual(try XCTUnwrap(timeline.latestOpposingShot(for: ak, at: 9)).time, 3)
        XCTAssertNil(timeline.latestOpposingShot(for: a, at: 9))
        for time in [Double.nan, .infinity, -.infinity] { XCTAssertNil(timeline.latestOpposingShot(for: hk, at: time)) }
        // Querying the future must not leak cached reaction state into rewind.
        XCTAssertNil(timeline.latestOpposingShot(for: hk, at: 2))
        XCTAssertEqual(try XCTUnwrap(timeline.latestOpposingShot(for: hk, at: 5)).time, 5)
    }

    func testUnknownDuplicateAndNonShotActorsFailClosed() {
        let keeper = player("keeper", team: .home, keeper: true)
        let a = player("a", team: .away)
        let timeline = ReplayFootballShotTimeline(touches: [touch("missing", at: 1), touch("a", at: 2, kind: .pass),
            touch("a", at: .nan), touch("a", at: -1)], players: [keeper, a])
        XCTAssertNil(timeline.latestOpposingShot(for: keeper, at: 10))
        let ambiguous = ReplayFootballShotTimeline(touches: [touch("a", at: 2)],
            players: [keeper, a, player("a", team: .home)])
        XCTAssertNil(ambiguous.latestOpposingShot(for: keeper, at: 10))
    }

    func testARecordedSavePassOrBlockSupersedesTheOldFlight() throws {
        let keeper = player("keeper", team: .home, keeper: true)
        let attacker = player("attacker", team: .away)
        for kind: ReplayNativeBallPhysics.TouchKind in [.save, .pass, .dribbleTouch, .header] {
            let timeline = ReplayFootballShotTimeline(touches: [touch("keeper", at: 1.2, kind: kind),
                touch("attacker", at: 1), touch("missing", at: 1.1)], players: [keeper, attacker])
            let shot = try XCTUnwrap(timeline.latestOpposingShot(for: keeper, at: 1.05))
            XCTAssertEqual(shot.supersededAt, 1.2)
            XCTAssertEqual(timeline.latestOpposingShot(for: keeper, at: 5), shot)
            XCTAssertNil(timeline.latestOpposingShot(for: keeper, at: 0.9))
        }
    }
}
