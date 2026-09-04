import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackPerspectiveNavigationTests: XCTestCase {
    func testAdjacentCoachPOVEntersPrivateReviewWithoutReplacingSquadTarget() throws {
        let store = ReplayStore()
        store.setCollaborationActive(true)
        store.broadcastPerspective("red-lb")
        store.setPlaying(true, broadcast: false)

        let nextID = try XCTUnwrap(
            PlaybackPerspectiveNavigation.adjacentPlayerID(
                in: store.selectedScenario.players,
                activeID: store.activePerspectiveID,
                localFallbackID: store.localPerspectiveID,
                offset: 1
            )
        )
        XCTAssertNotEqual(nextID, "red-lb")

        store.openLocalPlayerPOV(nextID)

        XCTAssertEqual(store.localPerspectiveID, nextID)
        XCTAssertEqual(store.coachFocusPerspectiveID, "red-lb")
        XCTAssertTrue(store.coachLockEnabled)
        XCTAssertTrue(store.isCoachLocalReview)
        XCTAssertFalse(store.isPlaying)
    }

    func testAdjacentFollowingPlayerDetachesOnlyWhenTargetIsOpened() throws {
        let coach = ReplayStore()
        coach.broadcastPerspective("red-lb")
        coach.setPlaying(true, broadcast: false)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))

        let nextID = try XCTUnwrap(
            PlaybackPerspectiveNavigation.adjacentPlayerID(
                in: player.selectedScenario.players,
                activeID: player.activePerspectiveID,
                localFallbackID: player.localPerspectiveID,
                offset: 1
            )
        )
        XCTAssertTrue(player.followsCoach)

        player.openLocalPlayerPOV(nextID)

        XCTAssertEqual(player.localPerspectiveID, nextID)
        XCTAssertFalse(player.followsCoach)
        XCTAssertTrue(player.isLocallyPaused)
        XCTAssertFalse(player.isPlaying)
    }

    func testNavigationWrapsAndFallsBackDeterministically() throws {
        let players = ReplayStore().selectedScenario.players
        let first = try XCTUnwrap(players.first?.id)
        let last = try XCTUnwrap(players.last?.id)

        XCTAssertEqual(
            PlaybackPerspectiveNavigation.adjacentPlayerID(
                in: players,
                activeID: "missing",
                localFallbackID: first,
                offset: -1
            ),
            last
        )
        XCTAssertNil(
            PlaybackPerspectiveNavigation.adjacentPlayerID(
                in: [],
                activeID: first,
                localFallbackID: first,
                offset: 1
            )
        )
    }
}
