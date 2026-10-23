import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationMoveAvailabilityTests: XCTestCase {
    func testHeldTimelineDisablesMoveWithoutChangingScrubCommitOrCancel() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.setPlaying(true, broadcast: false)
            XCTAssertTrue(store.beginTimelineScrub())
            XCTAssertTrue(store.previewTimelineScrub(to: 12))

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.playhead, 12)

            if commits {
                XCTAssertTrue(store.commitTimelineScrub(to: 14))
                XCTAssertEqual(store.playhead, 14)
            } else {
                store.cancelTimelineScrub()
                XCTAssertEqual(store.playhead, 5)
                store.seek(to: 12, broadcast: false)
            }
            XCTAssertTrue(store.isPlaying)
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testHeldWorldHandleDisablesMoveWithoutChangingItsPreviewOrCompletion() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.seek(to: 12, broadcast: false)
            let end = PitchPoint(x: mark.end.x + 0.5, z: mark.end.z)
            XCTAssertTrue(store.updateCoachMarkGeometry(
                id: mark.id, start: mark.start, end: end, broadcast: false))

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)

            if commits {
                XCTAssertTrue(store.commitCoachMarkGeometryPreview(
                    id: mark.id, start: mark.start, end: end))
                XCTAssertEqual(try currentMark(mark.id, in: store).end, end)
            } else {
                XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
                XCTAssertEqual(try currentMark(mark.id, in: store), mark)
            }
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testHeldJoystickDisablesMoveAndKeepsTheExactEndpointOwner() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.seek(to: 12, broadcast: false)
            let gestureID = UUID()
            let movement = PitchPoint(x: 0.5, z: -0.25)
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: gestureID, cumulativeDelta: movement))
            let owner = CoachMarkEndpointPreviewOwner(markID: mark.id, endpoint: .end)

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)

            if commits {
                XCTAssertEqual(store.commitCoachMarkEndpointPreview(
                    id: mark.id, gestureID: gestureID), movement)
            } else {
                XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
                XCTAssertEqual(try currentMark(mark.id, in: store), mark)
            }
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testOrdinaryReplayAndShapeMovesStillRetimeOnceAndUndoExactly() throws {
        for scenarioID in ["real-world-match-replay", "triangle-lock"] {
            let (store, mark) = try makeMark(scenarioID: scenarioID)
            store.seek(to: 12, broadcast: false)
            let baseline = store.marks
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))

            store.setPlaying(false, broadcast: false)
            XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: store.playhead))

            let moved = try currentMark(mark.id, in: store)
            XCTAssertEqual(moved.revealTime, 12)
            XCTAssertEqual(moved.hideTime, 20)
            XCTAssertEqual(moved.start, mark.start)
            XCTAssertEqual(moved.end, mark.end)
            XCTAssertEqual(moved.startTrackAnchor, mark.startTrackAnchor)
            XCTAssertEqual(moved.endTrackAnchor, mark.endTrackAnchor)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, baseline)
            XCTAssertEqual(store.playhead, 12)
        }
    }

    func testOriginalTimeDifferenceAndWindowBoundsRemainUnchanged() throws {
        let (store, mark) = try makeMark()
        for time: TimeInterval in [-1, 5, 5.04, 24.01, 31, 32, 33, .nan, .infinity] {
            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: time, in: store), "\(time)")
        }
        for time: TimeInterval in [0, 5.06, 12, 24] {
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: time, in: store), "\(time)")
        }
        XCTAssertTrue(store.setCoachMarkDuration(id: mark.id, duration: nil))
        let throughEnd = try currentMark(mark.id, in: store)
        XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(throughEnd, to: 32, in: store))
    }

    func testSavedPositionBoundsExplainWhyShorteningWindowCannotUnblockMove146() throws {
        let (store, original) = try makeMark()
        XCTAssertEqual(store.selectedScenario.duration, 32)
        XCTAssertTrue(store.setCoachMarkTracking(id: original.id, playerID: nil))
        let fixed = try XCTUnwrap(store.marks.first { $0.id == original.id && !$0.followsPlayerTracks },
                                 "Position keys require unlinking the automatically tracked mark first")
        XCTAssertFalse(fixed.followsPlayerTracks)
        let firstKeys = try XCTUnwrap(store.captureCoachMarkKeyframe(id: fixed.id)
            ? store.marks.first(where: { $0.id == fixed.id })?.keyframes : nil,
            "Stop if the first fixed-position key was not captured")
        XCTAssertEqual(firstKeys.map(\.time), [5])
        store.seek(to: 32, broadcast: false)
        let bothKeys = try XCTUnwrap(store.captureCoachMarkKeyframe(id: fixed.id)
            ? store.marks.first(where: { $0.id == fixed.id })?.keyframes : nil,
            "Stop if the clip-end position key was not captured")
        XCTAssertEqual(bothKeys.map(\.time), [5, 32])
        store.seek(to: 6, broadcast: false)
        let mark = try currentMark(original.id, in: store)
        XCTAssertEqual(mark.keyframes?.map(\.time), [5, 32])
        XCTAssertTrue(CoachMarkTimingPolicy.windowFits(revealTime: 6, displayDuration: 8, replayDuration: 32))
        let snapshot = store.makeSnapshot()
        let undoTitle = store.annotationUndoTitle
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: 6, in: store), .positionKeyBounds)
        XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: 6, in: store))
        XCTAssertEqual(PlaybackAnnotationMovePolicy.compactHint(mark, to: 6, in: store), "CHECK KEYS")
        XCTAssertTrue(PlaybackAnnotationMovePolicy.guidance(mark, to: 6, in: store).contains("Shortening In/Out does not move position keys"))
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: 6))
        XCTAssertEqual(store.makeSnapshot(), snapshot)
        XCTAssertEqual(store.annotationUndoTitle, undoTitle)

        XCTAssertTrue(store.setCoachMarkWindow(id: mark.id, start: 5, end: 6))
        let shorter = try currentMark(mark.id, in: store)
        XCTAssertEqual(shorter.keyframes, mark.keyframes)
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(shorter, to: 6, in: store), .positionKeyBounds)
        XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(shorter, to: 6, in: store))
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: 6))

        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 32, to: 31))
        let repaired = try currentMark(mark.id, in: store)
        XCTAssertNil(PlaybackAnnotationMovePolicy.blockReason(repaired, to: 6, in: store))
        XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(repaired, to: 6, in: store))
        XCTAssertEqual(PlaybackAnnotationMovePolicy.compactHint(repaired, to: 6, in: store), "SCRUB ABOVE")
        XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: 6))
        let moved = try currentMark(mark.id, in: store)
        XCTAssertEqual(moved.revealTime, 6)
        XCTAssertEqual(moved.hideTime, 7)
        XCTAssertEqual(moved.keyframes?.map(\.time), [6, 32])
        XCTAssertEqual(store.playhead, 6)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try currentMark(mark.id, in: store), repaired)
    }

    func testMoveReasonPriorityDistinguishesGestureTimeAndWindow146() throws {
        let (store, mark) = try makeMark()
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: .nan, in: store), .invalidTime)
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: 33, in: store), .invalidTime)
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: 5.04, in: store), .currentTime)
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: 25, in: store), .visibilityWindow)
        XCTAssertNil(PlaybackAnnotationMovePolicy.blockReason(mark, to: 12, in: store))
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertEqual(PlaybackAnnotationMovePolicy.blockReason(mark, to: .nan, in: store), .activeGesture)
        XCTAssertEqual(PlaybackAnnotationMovePolicy.guidance(mark, to: 12, in: store),
                       "Finish or cancel the current gesture first")
        store.cancelTimelineScrub()
    }

    func testVisibleTrackMoveGuardsItsLiveContextBeforeCommitting() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/SpatialAnnotationTimeline.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".gesture(editGesture(.move, width: width))"))
        XCTAssertTrue(source.contains(".help(\"Drag to move this mark in time\")"))
        let commit = try XCTUnwrap(source.range(of: "private func commitDrag()")?.lowerBound)
        let move = String(source[commit...])
        for guardText in ["guard editable", "edit.scenarioID == store.selectedScenarioID",
                          "edit.view == store.viewMode", "!store.isPlaying",
                          "store.marks.first(where: { $0.id == edit.mark.id }) == edit.mark"] {
            XCTAssertTrue(move.contains(guardText), guardText)
        }
        let gate = try XCTUnwrap(move.range(of: "guard editable")?.lowerBound)
        let mutation = try XCTUnwrap(move.range(of: "store.retimeCoachMark(id: edit.mark.id, to: start)")?.lowerBound)
        XCTAssertLessThan(gate, mutation)
        XCTAssertTrue(move.contains("SpatialAnnotationTimelineMath.movedStart(mark: edit.mark"))
    }

    private func assertStoreRejectsMove(_ mark: CoachMark, in store: ReplayStore,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let marks = store.marks
        let snapshot = store.makeSnapshot()
        let history = store.annotationUndoTitle
        XCTAssertFalse(store.canChangePlaybackView, file: file, line: line)
        // The current visible callback requests this pause before its retime.
        store.setPlaying(false, broadcast: false)
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: store.playhead), file: file, line: line)
        XCTAssertEqual(store.marks, marks, file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(store.annotationUndoTitle, history, file: file, line: line)
    }

    private func makeMark(scenarioID: String = "real-world-match-replay") throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: scenarioID)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        XCTAssertTrue(store.setCoachMarkDuration(id: mark.id, duration: 8))
        XCTAssertFalse(store.isDrawing)
        let timed = try currentMark(mark.id, in: store)
        XCTAssertEqual(timed.hideTime, 13)
        return (store, timed)
    }

    private func currentMark(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }
}
