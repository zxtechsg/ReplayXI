import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkEndpointNudgeTests: XCTestCase {
    func testNudgeMovesOnlyRequestedEndpointAndBroadcastsOnce() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: -0.25)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(adjusted.start, PitchPoint(x: 2.5, z: 2.75))
        XCTAssertEqual(adjusted.end, original.end)
        XCTAssertEqual(adjusted.kind, original.kind)
        XCTAssertEqual(adjusted.label, original.label)
        XCTAssertEqual(adjusted.revealTime, original.revealTime)
        XCTAssertEqual(adjusted.hideTime, original.hideTime)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(broadcasts[0].isPlaying)
        XCTAssertEqual(
            broadcasts[0].marks.first { $0.id == original.id },
            adjusted
        )
    }

    func testNudgeClampsRequestedEndpointToPitchBounds() throws {
        let store = ReplayStore()
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 33.75, z: 52)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 24, z: 42))
        )
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 2, z: 3)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(
            adjusted.start,
            PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
        )
        XCTAssertEqual(adjusted.end, original.end)
        XCTAssertEqual(broadcastCount, 1)

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 1, z: 1)
            )
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, adjusted)
        XCTAssertEqual(broadcastCount, 1)
    }

    func testNudgeCanMoveEndWithoutChangingStart() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: -0.25, z: 0.5)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(adjusted.start, original.start)
        XCTAssertEqual(adjusted.end, PitchPoint(x: 7.75, z: 12.5))
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcastCount, 1)
    }

    func testNudgeRejectsInvalidOrUnreadablyShortResultWithoutPublishing() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: .nan, z: 1)
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: .zero
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(
                    x: original.start.x - original.end.x,
                    z: original.start.z - original.end.z
                )
            )
        )

        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testNudgePreservesAuthoredFixtureMarksAndPlayerLabels() throws {
        let store = ReplayStore()
        let authored = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        let labelledPlayer = try XCTUnwrap(store.selectedScenario.players.first)
        let playerLabel = try XCTUnwrap(store.labelPlayer(labelledPlayer.id))
        let initialMarks = store.marks
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: authored.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: playerLabel.id,
                endpoint: .end,
                by: PitchPoint(x: 0, z: 0.5)
            )
        )

        XCTAssertEqual(store.marks, initialMarks)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoinedPlayerCannotNudgeCoachAnnotation() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        let initialMarks = store.marks
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        store.localRole = .player
        store.setCollaborationActive(true)

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )

        XCTAssertEqual(store.marks, initialMarks)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testNudgeCannotCommitAnUnfinishedGeometryPreview() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: PitchPoint(x: -2, z: 1),
                end: PitchPoint(x: 9, z: 14),
                broadcast: false
            )
        )
        let preview = try XCTUnwrap(store.marks.first { $0.id == original.id })
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )

        XCTAssertEqual(store.marks.first { $0.id == original.id }, preview)
        XCTAssertEqual(broadcastCount, 0)
        XCTAssertEqual(
            store.makeSnapshot().marks.first { $0.id == original.id },
            original
        )
    }

    func testJoystickPreviewPublishesMaskedPauseOnceThenOneGeometrySnapshot() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let gestureID = UUID()

        let first = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 0.25, z: 0)
            )
        )
        let fourth = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: -1)
            )
        )

        XCTAssertEqual(first.appliedDelta, PitchPoint(x: 0.25, z: 0))
        XCTAssertTrue(first.hasActiveTransaction)
        XCTAssertEqual(fourth.appliedDelta, PitchPoint(x: 1, z: -1))
        XCTAssertTrue(fourth.hasActiveTransaction)
        XCTAssertFalse(store.isPlaying, "The local pitch should freeze while precision editing.")
        XCTAssertEqual(broadcasts.count, 1, "Only the first accepted notch should pause the squad.")
        XCTAssertFalse(try XCTUnwrap(broadcasts.first).isPlaying)
        XCTAssertEqual(broadcasts[0].marks.first { $0.id == original.id }, original)

        let masked = store.makeSnapshot()
        XCTAssertFalse(masked.isPlaying, "A mid-gesture snapshot must retain the shared pause.")
        XCTAssertEqual(masked.marks.first { $0.id == original.id }, original)

        let committedDelta = try XCTUnwrap(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(committedDelta, PitchPoint(x: 1, z: -1))
        XCTAssertEqual(broadcasts.count, 2)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)
        XCTAssertEqual(
            broadcasts[1].marks.first { $0.id == original.id },
            store.marks.first { $0.id == original.id }
        )
    }

    func testSharedJoystickCancellationKeepsThePublishedPause() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: -0.5, z: 0.25)
            )
        )
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(broadcasts[0].isPlaying)
        XCTAssertEqual(broadcasts[0].marks.first { $0.id == original.id }, original)

        XCTAssertTrue(
            store.cancelCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcasts.count, 1, "Cancellation must retain the already-shared pause.")
    }

    func testJoystickCumulativePreviewAccountsForPartiallyClampedMultiNotchMove() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 33.75, z: 52)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 24, z: 42))
        )
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        let gestureID = UUID()

        let fourNotches = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: 1)
            )
        )
        XCTAssertEqual(fourNotches.appliedDelta, PitchPoint(x: 0.25, z: 0.5))
        XCTAssertEqual(
            store.marks.first { $0.id == original.id }?.start,
            PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
        )

        let threeNotches = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 0.75, z: 0.75)
            )
        )
        XCTAssertEqual(
            threeNotches.appliedDelta,
            PitchPoint(x: 0.25, z: 0.5),
            "Reducing a still-out-of-bounds request must not apply a false reverse notch."
        )
        XCTAssertEqual(
            store.marks.first { $0.id == original.id }?.start,
            PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
        )
        XCTAssertEqual(broadcastCount, 0)

        XCTAssertEqual(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID),
            PitchPoint(x: 0.25, z: 0.5)
        )
        XCTAssertEqual(broadcastCount, 1)
    }

    func testOutwardJoystickRequestAtPitchCornerStaysANonTransactionalNoOp() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(
            store.registerPitchTap(
                PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
            )
        )
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 24, z: 42))
        )
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        let gestureID = UUID()

        let result = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: 1)
            )
        )

        XCTAssertEqual(result.appliedDelta, .zero)
        XCTAssertFalse(result.hasActiveTransaction)
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertNil(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoystickReturnedToCentreRollsBackAndResumesWithoutSnapshot() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: -0.5)
            )
        )
        let centred = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: .zero
            )
        )
        XCTAssertTrue(centred.hasActiveTransaction)
        XCTAssertEqual(centred.appliedDelta, .zero)

        XCTAssertNil(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoystickCancellationRestoresGeometryAndPlaybackWithoutSnapshot() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: -0.75, z: 0.5)
            )
        )
        XCTAssertNotEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertFalse(store.isPlaying)

        XCTAssertTrue(
            store.cancelCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcastCount, 0)
        XCTAssertFalse(store.cancelCoachMarkEndpointPreview(id: original.id))
    }

    func testInvalidFinalJoystickSampleRollsBackInsteadOfCommittingStalePreview() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: -1, z: 0)
            )
        )
        XCTAssertNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(
                    x: original.start.x - original.end.x,
                    z: original.start.z - original.end.z
                )
            )
        )

        XCTAssertNil(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoystickTransactionRejectsTransportScenarioAndPOVInterleavingThenPublishesOnce() throws {
        let store = ReplayStore()
        store.selectScenario(id: "eleven-eyes", broadcast: false)
        store.seek(to: 8, broadcast: false)
        let trackedPlayer = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        let alternatePlayer = try XCTUnwrap(
            store.selectedScenario.players.first { $0.id != trackedPlayer.id }
        )
        let originalStart = trackedPlayer.pose(at: store.playhead).position
        let originalEnd = PitchPoint(x: originalStart.x + 4, z: originalStart.z + 7)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(originalStart))
        let original = try XCTUnwrap(store.registerPitchTap(originalEnd))
        XCTAssertNotNil(original.startTrackAnchor)
        XCTAssertNotNil(original.endTrackAnchor)
        store.setPlaying(true, broadcast: false)

        let originalScenarioID = store.selectedScenarioID
        let originalPlayhead = store.playhead
        let originalRate = store.playbackRate
        let originalViewMode = store.viewMode
        let originalPerspectiveID = store.localPerspectiveID
        let alternateScenario = try XCTUnwrap(
            store.scenarios.first { $0.id != originalScenarioID }
        )
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 0.5, z: 0.25)
            )
        )
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertFalse(store.isPlaying)

        store.togglePlayback()
        store.setPlaying(true)
        store.seek(to: 14, broadcast: false)
        store.setPlaybackRate(4)
        store.selectScenario(id: alternateScenario.id)
        store.setViewMode(.touchline)
        store.openLocalPlayerPOV(alternatePlayer.id)
        store.setLocalPerspective(alternatePlayer.id)
        store.broadcastPerspective(alternatePlayer.id)
        XCTAssertFalse(store.beginLocalReview(at: 12))
        store.advance(by: 2)
        store.resetScenario()

        XCTAssertEqual(store.selectedScenarioID, originalScenarioID)
        XCTAssertEqual(store.playhead, originalPlayhead)
        XCTAssertEqual(store.playbackRate, originalRate)
        XCTAssertEqual(store.viewMode, originalViewMode)
        XCTAssertEqual(store.localPerspectiveID, originalPerspectiveID)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(broadcasts.isEmpty)

        let finalPreview = try XCTUnwrap(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: 0.5)
            )
        )
        XCTAssertEqual(finalPreview.appliedDelta, PitchPoint(x: 1, z: 0.5))
        XCTAssertEqual(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID),
            PitchPoint(x: 1, z: 0.5)
        )

        let committed = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(store.playhead, originalPlayhead)
        XCTAssertEqual(
            committed.resolvedGeometry(in: store.selectedScenario, at: originalPlayhead),
            ResolvedCoachMarkGeometry(
                start: originalStart,
                end: PitchPoint(x: originalEnd.x + 1, z: originalEnd.z + 0.5)
            )
        )
        let laterTime: TimeInterval = 14
        let laterPlayerPosition = trackedPlayer.pose(at: laterTime).position
        let laterGeometry = committed.resolvedGeometry(in: store.selectedScenario, at: laterTime)
        XCTAssertEqual(laterGeometry.start, laterPlayerPosition)
        XCTAssertEqual(laterGeometry.end.x - laterGeometry.start.x, 5, accuracy: 0.000_1)
        XCTAssertEqual(laterGeometry.end.z - laterGeometry.start.z, 7.5, accuracy: 0.000_1)
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(broadcasts[0].playhead, originalPlayhead)
        XCTAssertEqual(broadcasts[0].marks.first { $0.id == original.id }, committed)
    }

    func testJoystickTransactionRejectsAnnotationAndRemoteInterleavingThenCancelsWithoutSnapshot() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        let originalMarks = store.marks
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let gestureID = UUID()

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: -0.75, z: 0.5)
            )
        )
        let previewMarks = store.marks
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: 0.25, z: 0)
            )
        )
        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: PitchPoint(x: -3, z: 0),
                end: PitchPoint(x: 6, z: 9)
            )
        )
        XCTAssertFalse(store.retimeCoachMark(id: original.id, to: 10))
        XCTAssertFalse(store.setCoachMarkDuration(id: original.id, duration: 12))
        XCTAssertFalse(store.updateCoachMarkLabel(id: original.id, label: "Changed"))
        XCTAssertFalse(store.setCoachMarkTracking(id: original.id, playerID: "navy-rw"))
        XCTAssertFalse(store.removeCoachMark(id: original.id))
        let labelledPlayer = try XCTUnwrap(store.selectedScenario.players.first)
        XCTAssertNil(store.labelPlayer(labelledPlayer.id))
        store.beginDrawing(.danger)
        store.addPresetMark()
        store.undoMark()
        store.clearMarks()
        XCTAssertFalse(store.applyRemote(store.makeSnapshot()))

        XCTAssertEqual(store.marks, previewMarks)
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertTrue(broadcasts.isEmpty)

        XCTAssertTrue(
            store.cancelCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(store.marks, originalMarks)
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertTrue(broadcasts.isEmpty)
    }

    func testRepeatedCollaborationStateDoesNotCancelAnOwnedJoystickPreview() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setCollaborationActive(true)
        let gestureID = UUID()
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 0.5, z: 0.25)
            )
        )
        let previewGeometry = store.marks.first { $0.id == original.id }

        store.setCollaborationActive(true)

        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(
            store.activeCoachMarkEndpointPreviewOwner,
            CoachMarkEndpointPreviewOwner(markID: original.id, endpoint: .end)
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, previewGeometry)
        XCTAssertEqual(broadcastCount, 1)
        XCTAssertEqual(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID),
            PitchPoint(x: 0.5, z: 0.25)
        )
        XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
        XCTAssertEqual(broadcastCount, 2)
    }

    func testLifecycleCancelledPinchCannotReopenUntilItsEndIsAcknowledged() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        let interruptedGestureID = UUID()
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: interruptedGestureID,
                cumulativeDelta: PitchPoint(x: -0.5, z: 0.25)
            )
        )

        store.setCollaborationActive(false)

        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertFalse(store.isPlaying)
        XCTAssertNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: interruptedGestureID,
                cumulativeDelta: PitchPoint(x: -0.75, z: 0.5)
            ),
            "Another sample from the interrupted physical pinch must not reopen editing."
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertEqual(broadcastCount, 1)

        // The UI delivers commit/cancel only when that physical pinch lifts.
        XCTAssertNil(
            store.commitCoachMarkEndpointPreview(
                id: original.id,
                gestureID: interruptedGestureID
            )
        )
        let nextGestureID = UUID()
        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                gestureID: nextGestureID,
                cumulativeDelta: PitchPoint(x: -0.25, z: 0)
            )
        )
        XCTAssertTrue(
            store.cancelCoachMarkEndpointPreview(id: original.id, gestureID: nextGestureID)
        )
    }

    func testCollaborationActivationRollsBackDirectHandlePreview() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        let previewStart = PitchPoint(x: original.start.x - 1, z: original.start.z + 0.5)
        let previewEnd = PitchPoint(x: original.end.x + 1, z: original.end.z + 0.5)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: previewStart,
                end: previewEnd,
                broadcast: false
            )
        )
        XCTAssertNotEqual(store.marks.first { $0.id == original.id }, original)

        store.setCollaborationActive(true)

        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertFalse(store.cancelCoachMarkGeometryPreview(id: original.id))
        XCTAssertTrue(store.isCollaborationActive)
    }

    func testImmersiveExitRollsBackPreviewPausesAndPublishesAtMostOneSnapshot() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        let gestureID = UUID()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        XCTAssertNotNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 0.75, z: -0.25)
            )
        )

        store.prepareForImmersiveExit()
        store.prepareForImmersiveExit()

        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.isActivelyPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(try XCTUnwrap(broadcasts.first).isPlaying)
        XCTAssertEqual(broadcasts[0].marks.first { $0.id == original.id }, original)
        XCTAssertNil(
            store.previewCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: 1, z: 0)
            )
        )
        XCTAssertFalse(
            store.cancelCoachMarkEndpointPreview(id: original.id, gestureID: gestureID)
        )
        XCTAssertEqual(broadcasts.count, 1)
    }

    private func makeCoachMark(in store: ReplayStore) throws -> CoachMark {
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        return try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 8, z: 12))
        )
    }
}
