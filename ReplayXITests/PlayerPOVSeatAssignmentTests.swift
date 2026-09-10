import XCTest
@testable import ReplayXI

@MainActor
final class PlayerPOVSeatAssignmentTests: XCTestCase {
    func testIncomingHeartbeatPreservesPrivatePOVUntilCoordinatorRejoin() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 8_000)
        let participantID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000801")!
        let coachID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000802")!
        let coachParticipantID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000803")!
        let assignedPlayerID = "navy-rb"
        let privatePlayerID = "red-lb"
        let sharedPlayerID = "navy-rw"

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = LegacySnapshotCoordinator(
            store: player,
            receiveDate: { receivedAt }
        )
        coordinator.state = .joined
        coordinator.localParticipantID = participantID
        coordinator.authoritativeCoachID = coachID
        coordinator.authoritativeCoachParticipantID = coachParticipantID

        coordinator.receiveForTesting(
            syncCommand(
                sequence: 1,
                coachID: coachID,
                snapshot: coachSnapshot(
                    participantID: participantID,
                    assignedPlayerID: assignedPlayerID,
                    sharedPlayerID: sharedPlayerID,
                    playhead: 5
                ),
                sentAt: receivedAt
            ),
            sourceParticipantID: coachParticipantID
        )

        XCTAssertEqual(player.localPerspectiveID, assignedPlayerID)
        XCTAssertEqual(player.activePerspectiveID, sharedPlayerID)
        XCTAssertTrue(player.followsCoach)
        XCTAssertFalse(player.isLocallyPaused)

        player.openLocalPlayerPOV(privatePlayerID)
        XCTAssertEqual(player.localPerspectiveID, privatePlayerID)
        XCTAssertEqual(player.activePerspectiveID, privatePlayerID)
        XCTAssertFalse(player.followsCoach)
        XCTAssertTrue(player.isLocallyPaused)

        coordinator.receiveForTesting(
            syncCommand(
                sequence: 2,
                coachID: coachID,
                snapshot: coachSnapshot(
                    participantID: participantID,
                    assignedPlayerID: assignedPlayerID,
                    sharedPlayerID: sharedPlayerID,
                    playhead: 12
                ),
                sentAt: receivedAt
            ),
            sourceParticipantID: coachParticipantID
        )

        XCTAssertEqual(player.localPerspectiveID, privatePlayerID)
        XCTAssertEqual(player.activePerspectiveID, privatePlayerID)
        XCTAssertEqual(player.playhead, 5, accuracy: 0.000_1)
        XCTAssertFalse(player.followsCoach)
        XCTAssertTrue(player.isLocallyPaused)

        coordinator.setFollowingCoach(true)

        XCTAssertEqual(player.playhead, 12, accuracy: 0.000_1)
        XCTAssertEqual(player.localPerspectiveID, assignedPlayerID)
        XCTAssertEqual(player.activePerspectiveID, sharedPlayerID)
        XCTAssertTrue(player.followsCoach)
        XCTAssertFalse(player.isLocallyPaused)
    }

    func testCoachReleaseReturnsRejoinedPlayerToAssignedPOV() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        let participantID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000901")!
        let coachID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000902")!
        let coachParticipantID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000903")!
        let assignedPlayerID = "navy-rb"

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = LegacySnapshotCoordinator(
            store: player,
            receiveDate: { receivedAt }
        )
        coordinator.state = .joined
        coordinator.localParticipantID = participantID
        coordinator.authoritativeCoachID = coachID
        coordinator.authoritativeCoachParticipantID = coachParticipantID

        coordinator.receiveForTesting(
            syncCommand(
                sequence: 1,
                coachID: coachID,
                snapshot: coachSnapshot(
                    participantID: participantID,
                    assignedPlayerID: assignedPlayerID,
                    sharedPlayerID: "navy-rw",
                    playhead: 4
                ),
                sentAt: receivedAt
            ),
            sourceParticipantID: coachParticipantID
        )
        player.openLocalPlayerPOV("red-lb")

        coordinator.receiveForTesting(
            syncCommand(
                sequence: 2,
                coachID: coachID,
                snapshot: coachSnapshot(
                    participantID: participantID,
                    assignedPlayerID: assignedPlayerID,
                    sharedPlayerID: nil,
                    playhead: 9
                ),
                sentAt: receivedAt
            ),
            sourceParticipantID: coachParticipantID
        )

        XCTAssertEqual(player.activePerspectiveID, "red-lb")
        coordinator.setFollowingCoach(true)

        XCTAssertEqual(player.localPerspectiveID, assignedPlayerID)
        XCTAssertEqual(player.activePerspectiveID, assignedPlayerID)
        XCTAssertFalse(player.coachLockEnabled)
        XCTAssertEqual(player.playhead, 9, accuracy: 0.000_1)
    }

    private func coachSnapshot(
        participantID: UUID,
        assignedPlayerID: String,
        sharedPlayerID: String?,
        playhead: TimeInterval
    ) -> SharedPlaybackSnapshot {
        let store = ReplayStore()
        store.seek(to: playhead, broadcast: false)
        store.participantSeatAssignments = [participantID: assignedPlayerID]
        if let sharedPlayerID {
            store.broadcastPerspective(sharedPlayerID)
        }
        return store.makeSnapshot()
    }

    private func syncCommand(
        sequence: UInt64,
        coachID: UUID,
        snapshot: SharedPlaybackSnapshot,
        sentAt: Date
    ) -> SharedCommand {
        SharedCommand(
            kind: .sync,
            sequence: sequence,
            authorID: coachID,
            sentAt: sentAt,
            authorRole: .coach,
            snapshot: snapshot,
            mark: nil
        )
    }
}
