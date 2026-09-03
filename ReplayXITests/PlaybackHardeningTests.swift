import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackHardeningTests: XCTestCase {
    func testSeekingOrRestoringPlaybackAtReplayEndStaysStopped() {
        let store = ReplayStore()
        let duration = store.selectedScenario.duration

        store.seek(to: duration - 1, broadcast: false)
        store.setPlaying(true, broadcast: false)
        store.seek(to: duration, broadcast: false)

        XCTAssertEqual(store.playhead, duration, accuracy: 0.000_1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.makeSnapshot().isPlaying)

        store.setPlaying(true, broadcast: false)

        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.makeSnapshot().isPlaying)
    }

    func testPausingInsideTerminalToleranceDoesNotRewind() {
        let store = ReplayStore()
        let nearEnd = store.selectedScenario.duration - 0.02
        store.seek(to: nearEnd, broadcast: false)
        store.setPlaying(true, broadcast: false)

        store.togglePlayback(broadcast: false)

        XCTAssertEqual(store.playhead, nearEnd, accuracy: 0.000_1)
        XCTAssertFalse(store.isPlaying)

        store.togglePlayback(broadcast: false)

        XCTAssertEqual(store.playhead, 0, accuracy: 0.000_1)
        XCTAssertTrue(store.isPlaying)
    }

    func testJoinedPlayerCannotIssueAuthoritativeTransportChanges() {
        let store = ReplayStore()
        store.localRole = .player
        store.setCollaborationActive(true)
        store.seek(to: 7, broadcast: false)
        store.setPlaybackRate(0.75, broadcast: false)

        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        store.seek(to: 18, broadcast: true)
        store.setPlaybackRate(4, broadcast: true)

        XCTAssertEqual(store.playhead, 7, accuracy: 0.000_1)
        XCTAssertEqual(store.playbackRate, 0.75, accuracy: 0.000_1)
        XCTAssertTrue(broadcasts.isEmpty)

        store.setFollowingCoach(false)
        store.seek(to: 18, broadcast: false)
        store.setPlaybackRate(2, broadcast: false)

        XCTAssertEqual(store.playhead, 18, accuracy: 0.000_1)
        XCTAssertEqual(store.playbackRate, 2, accuracy: 0.000_1)
        XCTAssertTrue(store.isLocallyPaused)
    }

    func testGeometryPreviewNeverEntersSharedSnapshotUntilCommit() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 8, z: 12))
        )
        let coordinator = SquadSessionCoordinator(store: store)
        store.setPlaybackRate(1)

        let originalPublished = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()?.marks.first { $0.id == mark.id }
        )
        let previewStart = PitchPoint(x: -6, z: 5)
        let previewEnd = PitchPoint(x: 4, z: 20)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: previewEnd,
                broadcast: false
            )
        )
        let localPreview = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(localPreview.start, previewStart)
        XCTAssertEqual(localPreview.end, previewEnd)

        let snapshotDuringPreview = try XCTUnwrap(
            store.makeSnapshot().marks.first { $0.id == mark.id }
        )
        XCTAssertEqual(snapshotDuringPreview.start, originalPublished.start)
        XCTAssertEqual(snapshotDuringPreview.end, originalPublished.end)

        // An unrelated shared action must not accidentally commit the drag.
        store.setPlaybackRate(2)
        let unrelatedPublish = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()?.marks.first { $0.id == mark.id }
        )
        XCTAssertEqual(unrelatedPublish.start, originalPublished.start)
        XCTAssertEqual(unrelatedPublish.end, originalPublished.end)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: previewEnd
            )
        )
        let committed = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()?.marks.first { $0.id == mark.id }
        )
        XCTAssertEqual(committed.start, previewStart)
        XCTAssertEqual(committed.end, previewEnd)
    }

    func testInvalidGeometryDragCompletionRollsBackPreview() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
        let mark = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 7, z: 11))
        )
        let previewStart = PitchPoint(x: -5, z: 4)
        let previewEnd = PitchPoint(x: 3, z: 17)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: previewEnd,
                broadcast: false
            )
        )
        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: .infinity, z: 4),
                end: previewEnd
            )
        )

        let rolledBack = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(rolledBack.start, mark.start)
        XCTAssertEqual(rolledBack.end, mark.end)
        let published = try XCTUnwrap(
            store.makeSnapshot().marks.first { $0.id == mark.id }
        )
        XCTAssertEqual(published.start, mark.start)
        XCTAssertEqual(published.end, mark.end)
    }

    func testCancelledGeometryPreviewRollsBackWithoutPublishing() throws {
        let store = ReplayStore()
        let coordinator = SquadSessionCoordinator(store: store)
        store.selectScenario(id: ExperienceKind.squadReplay.rawValue)
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 7, z: 11)))
        let publishedBefore = try XCTUnwrap(
            coordinator.snapshotForHeartbeat()?.marks.first { $0.id == mark.id }
        )

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: -5, z: 4),
                end: PitchPoint(x: 3, z: 17),
                broadcast: false
            )
        )
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        let restored = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(restored.start, mark.start)
        XCTAssertEqual(restored.end, mark.end)
        XCTAssertEqual(
            coordinator.snapshotForHeartbeat()?.marks.first { $0.id == mark.id },
            publishedBefore
        )
        XCTAssertFalse(store.cancelCoachMarkGeometryPreview(id: mark.id))
    }

    func testInterruptedStrokeClearsPointButKeepsToolArmed() {
        let store = ReplayStore()
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 4)))

        store.resetPendingAnnotationPointAfterInterruption()

        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.selectedTool, .pass)
        XCTAssertNil(store.pendingDrawStart)
    }

    func testRejectedAnnotationDoesNotPoisonCoachSequence() {
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = SquadSessionCoordinator(store: player)
        coordinator.state = .joined

        let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000101")!
        let coachParticipantID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000102")!
        coordinator.authoritativeCoachID = coachID
        coordinator.authoritativeCoachParticipantID = coachParticipantID

        let initial = command(
            kind: .sync,
            sequence: 1,
            authorID: coachID,
            role: .coach,
            snapshot: player.makeSnapshot()
        )
        coordinator.receiveForTesting(initial, sourceParticipantID: coachParticipantID)

        let invalidMark = CoachMark(
            kind: .pass,
            start: PitchPoint(x: .infinity, z: 0),
            end: PitchPoint(x: 2, z: 3),
            label: "Invalid lane",
            revealTime: 4
        )
        let rejected = command(
            kind: .coachAnnotation,
            sequence: 100,
            authorID: coachID,
            role: .coach,
            mark: invalidMark
        )
        coordinator.receiveForTesting(rejected, sourceParticipantID: coachParticipantID)

        let coach = ReplayStore()
        coach.seek(to: 11, broadcast: false)
        coach.setPlaybackRate(1.5, broadcast: false)
        coach.setPlaying(true, broadcast: false)
        let recovery = command(
            kind: .sync,
            sequence: 2,
            authorID: coachID,
            role: .coach,
            snapshot: coach.makeSnapshot()
        )
        coordinator.receiveForTesting(recovery, sourceParticipantID: coachParticipantID)

        XCTAssertEqual(player.playhead, 11, accuracy: 0.000_1)
        XCTAssertEqual(player.playbackRate, 1.5, accuracy: 0.000_1)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.marks.contains(invalidMark))
    }

    func testDuplicateValidAnnotationStillRejectsOlderFullSnapshot() {
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = SquadSessionCoordinator(store: player)
        coordinator.state = .joined

        let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000301")!
        let coachParticipantID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000302")!
        coordinator.authoritativeCoachID = coachID
        coordinator.authoritativeCoachParticipantID = coachParticipantID

        let mark = CoachMark(
            kind: .run,
            start: PitchPoint(x: 2, z: 4),
            end: PitchPoint(x: 8, z: 15),
            label: "Outside run",
            revealTime: 6
        )
        let base = player.makeSnapshot()
        let initialSnapshot = SharedPlaybackSnapshot(
            scenarioID: base.scenarioID,
            playhead: base.playhead,
            isPlaying: base.isPlaying,
            playbackRate: base.playbackRate,
            viewMode: base.viewMode,
            coachFocusPerspectiveID: base.coachFocusPerspectiveID,
            coachLockEnabled: base.coachLockEnabled,
            marks: base.marks + [mark],
            seatAssignments: base.seatAssignments,
            showsLaneLens: base.showsLaneLens,
            sharedPitchAnchorID: base.sharedPitchAnchorID,
            triangleLockMode: base.triangleLockMode,
            shapeFocusStage: base.shapeFocusStage
        )
        coordinator.receiveForTesting(
            command(
                kind: .sync,
                sequence: 1,
                authorID: coachID,
                role: .coach,
                snapshot: initialSnapshot
            ),
            sourceParticipantID: coachParticipantID
        )

        let annotation = command(
            kind: .coachAnnotation,
            sequence: 5,
            authorID: coachID,
            role: .coach,
            mark: mark
        )
        coordinator.receiveForTesting(annotation, sourceParticipantID: coachParticipantID)
        XCTAssertEqual(player.marks.filter { $0.id == mark.id }.count, 1)

        let staleSnapshot = SharedPlaybackSnapshot(
            scenarioID: base.scenarioID,
            playhead: 2,
            isPlaying: false,
            playbackRate: base.playbackRate,
            viewMode: base.viewMode,
            coachFocusPerspectiveID: base.coachFocusPerspectiveID,
            coachLockEnabled: base.coachLockEnabled,
            marks: base.marks,
            seatAssignments: base.seatAssignments,
            showsLaneLens: base.showsLaneLens,
            sharedPitchAnchorID: base.sharedPitchAnchorID,
            triangleLockMode: base.triangleLockMode,
            shapeFocusStage: base.shapeFocusStage
        )
        coordinator.receiveForTesting(
            command(
                kind: .sync,
                sequence: 4,
                authorID: coachID,
                role: .coach,
                snapshot: staleSnapshot
            ),
            sourceParticipantID: coachParticipantID
        )

        XCTAssertTrue(player.marks.contains(mark))
        XCTAssertNotEqual(player.playhead, 2)
    }

    func testSpoofedStateRequestCannotConsumeCoachSequenceNamespace() {
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = SquadSessionCoordinator(store: player)
        coordinator.state = .joined

        let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000201")!
        let coachParticipantID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000202")!
        let otherParticipantID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000203")!
        coordinator.authoritativeCoachID = coachID

        let spoofedRequest = command(
            kind: .requestState,
            sequence: 100,
            authorID: coachID,
            role: .player
        )
        coordinator.receiveForTesting(spoofedRequest, sourceParticipantID: otherParticipantID)

        let coach = ReplayStore()
        coach.seek(to: 9, broadcast: false)
        let firstCoachSync = command(
            kind: .sync,
            sequence: 1,
            authorID: coachID,
            role: .coach,
            snapshot: coach.makeSnapshot()
        )
        coordinator.receiveForTesting(firstCoachSync, sourceParticipantID: coachParticipantID)

        XCTAssertEqual(coordinator.authoritativeCoachParticipantID, coachParticipantID)
        XCTAssertEqual(player.playhead, 9, accuracy: 0.000_1)
    }

    func testParticipantJoinSnapshotPreservesCommittedReviewDuringScrub() throws {
        let store = ReplayStore()
        let coordinator = SquadSessionCoordinator(store: store)
        store.seek(to: 4, broadcast: false)
        store.setPlaybackRate(1, broadcast: false)
        store.setPlaying(true)

        store.setPlaying(false, broadcast: false)
        store.seek(to: 18, broadcast: false)
        let participantID = UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000204")!
        store.participantSeatAssignments[participantID] = "navy-rw"

        let lateJoinSnapshot = try XCTUnwrap(
            coordinator.publishParticipantChangeForTesting(elapsed: 2)
        )

        XCTAssertEqual(lateJoinSnapshot.playhead, 6, accuracy: 0.000_1)
        XCTAssertTrue(lateJoinSnapshot.isPlaying)
        XCTAssertEqual(lateJoinSnapshot.seatAssignments[participantID], "navy-rw")
        XCTAssertEqual(store.playhead, 18, accuracy: 0.000_1)
        XCTAssertFalse(store.isPlaying)
    }

    func testRewindSeekAndRateChangeResetHeartbeatProjectionOrigin() throws {
        let store = ReplayStore()
        let coordinator = SquadSessionCoordinator(store: store)
        store.seek(to: 12, broadcast: false)
        store.setPlaying(true)

        XCTAssertEqual(
            try XCTUnwrap(coordinator.advancePublishedTimelineForHeartbeat(by: 2)).playhead,
            14,
            accuracy: 0.000_1
        )

        store.seek(to: 5)
        store.setPlaybackRate(2)
        let projected = try XCTUnwrap(
            coordinator.advancePublishedTimelineForHeartbeat(by: 1.5)
        )

        XCTAssertEqual(projected.playhead, 8, accuracy: 0.000_1)
        XCTAssertEqual(projected.playbackRate, 2, accuracy: 0.000_1)
        XCTAssertTrue(projected.isPlaying)
    }

    private func command(
        kind: SharedCommandKind,
        sequence: UInt64,
        authorID: UUID,
        role: SquadRole,
        snapshot: SharedPlaybackSnapshot? = nil,
        mark: CoachMark? = nil
    ) -> SharedCommand {
        SharedCommand(
            kind: kind,
            sequence: sequence,
            authorID: authorID,
            sentAt: Date(timeIntervalSinceReferenceDate: TimeInterval(sequence)),
            authorRole: role,
            snapshot: snapshot,
            mark: mark
        )
    }
}
