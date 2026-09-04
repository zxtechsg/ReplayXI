import XCTest
@testable import ReplayXI

@MainActor
final class LocalPOVIsolationTests: XCTestCase {
    func testTappingCurrentCoachPOVDoesNotPauseOrPublish() {
        let store = ReplayStore()
        store.setCollaborationActive(true)
        store.broadcastPerspective("red-lb")
        store.setPlaying(true, broadcast: false)

        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let statusBeforeTap = store.statusMessage

        store.openLocalPlayerPOV("red-lb")

        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)
        XCTAssertFalse(store.isCoachLocalReview)
        XCTAssertEqual(store.localPerspectiveID, "red-lb")
        XCTAssertEqual(store.activePerspectiveID, "red-lb")
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.coachFocusPerspectiveID, "red-lb")
        XCTAssertTrue(store.coachLockEnabled)
        XCTAssertEqual(store.statusMessage, statusBeforeTap)
        XCTAssertTrue(broadcasts.isEmpty)
    }

    func testTappingCurrentSharedPOVDoesNotDetachFollowingPlayer() throws {
        let coach = ReplayStore()
        coach.broadcastPerspective("red-lb")
        coach.setPlaying(true, broadcast: false)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))
        let assignedPerspectiveBeforeTap = player.localPerspectiveID
        let statusBeforeTap = player.statusMessage
        var broadcasts: [SharedPlaybackSnapshot] = []
        player.onBroadcastSnapshot = { broadcasts.append($0) }

        XCTAssertEqual(player.activePerspectiveID, "red-lb")
        XCTAssertNotEqual(assignedPerspectiveBeforeTap, "red-lb")

        player.openLocalPlayerPOV("red-lb")

        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.followsCoach)
        XCTAssertFalse(player.isLocallyPaused)
        XCTAssertEqual(player.localPerspectiveID, assignedPerspectiveBeforeTap)
        XCTAssertEqual(player.activePerspectiveID, "red-lb")
        XCTAssertEqual(player.viewMode, .firstPerson)
        XCTAssertEqual(player.statusMessage, statusBeforeTap)
        XCTAssertTrue(broadcasts.isEmpty)
    }

    func testPrivateCoachCameraChangeKeepsPublishedSquadPOVUntilExplicitShare() throws {
        let store = ReplayStore()
        let coordinator = SquadSessionCoordinator(store: store)
        coordinator.state = .joined
        coordinator.authoritativeCoachID = coordinator.localID
        store.setCollaborationActive(true)
        store.broadcastPerspective("navy-rw")
        store.setPlaying(true)

        store.openLocalPlayerPOV("red-lb")
        let publishedBeforeCameraChange = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()
        )
        XCTAssertTrue(store.isCoachLocalReview)
        XCTAssertEqual(store.localPerspectiveID, "red-lb")
        XCTAssertEqual(publishedBeforeCameraChange.viewMode, .firstPerson)
        XCTAssertEqual(publishedBeforeCameraChange.coachFocusPerspectiveID, "navy-rw")
        XCTAssertTrue(publishedBeforeCameraChange.coachLockEnabled)
        XCTAssertFalse(publishedBeforeCameraChange.isPlaying)

        store.setViewMode(.touchline)

        let publishedAfterCameraChange = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()
        )
        XCTAssertTrue(store.isCoachLocalReview)
        XCTAssertEqual(store.localPerspectiveID, "red-lb")
        XCTAssertEqual(store.viewMode, .touchline)
        XCTAssertEqual(
            publishedAfterCameraChange.viewMode,
            publishedBeforeCameraChange.viewMode
        )
        XCTAssertEqual(
            publishedAfterCameraChange.coachFocusPerspectiveID,
            publishedBeforeCameraChange.coachFocusPerspectiveID
        )
        XCTAssertEqual(
            publishedAfterCameraChange.coachLockEnabled,
            publishedBeforeCameraChange.coachLockEnabled
        )
        XCTAssertEqual(
            publishedAfterCameraChange.playhead,
            publishedBeforeCameraChange.playhead,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            publishedAfterCameraChange.isPlaying,
            publishedBeforeCameraChange.isPlaying
        )

        store.broadcastPerspective("red-lb")

        let explicitlyShared = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertFalse(store.isCoachLocalReview)
        XCTAssertEqual(explicitlyShared.viewMode, .firstPerson)
        XCTAssertEqual(explicitlyShared.coachFocusPerspectiveID, "red-lb")
        XCTAssertTrue(explicitlyShared.coachLockEnabled)
    }
}
