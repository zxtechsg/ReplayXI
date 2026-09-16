import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationEditHistoryTests: XCTestCase {
    private func makeMark(_ store: ReplayStore, kind: CoachMarkKind = .pass) throws -> CoachMark {
        store.beginDrawing(kind)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -4, z: 2)))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 4, z: 10)))
    }

    func testAddUndoRedoPreserveIDTimingFixturesAndPauseWithoutMovingPOV() throws {
        let store = ReplayStore()
        let fixtures = store.marks
        XCTAssertFalse(store.hasAnnotationEditHistory)
        store.seek(to: 9)
        let mark = try makeMark(store)
        let pov = store.activePerspectiveID
        XCTAssertEqual(store.annotationUndoTitle, "Undo add")
        store.setPlaying(true)
        var snapshots: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { snapshots.append($0) }

        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, fixtures)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertEqual(store.activePerspectiveID, pov)
        XCTAssertFalse(store.canUndoAnnotationEdit)
        XCTAssertTrue(store.canRedoAnnotationEdit)
        XCTAssertTrue(store.hasAnnotationEditHistory, "The history shelf must stay reachable with no new marks")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.last?.marks, fixtures)

        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, fixtures + [mark])
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertFalse(store.canRedoAnnotationEdit)
        XCTAssertTrue(store.canUndoAnnotationEdit)
    }

    func testEraseAndClearRestoreExactMarksInTheirOriginalOrder() throws {
        let store = ReplayStore()
        let fixtures = store.marks
        let first = try makeMark(store)
        let second = try makeMark(store, kind: .run)
        let third = try makeMark(store, kind: .space)
        let all = store.marks
        XCTAssertTrue(store.removeCoachMark(id: second.id))
        XCTAssertEqual(store.annotationUndoTitle, "Undo erase")
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, all)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, fixtures + [first, third])

        store.clearMarks()
        XCTAssertEqual(store.marks, fixtures)
        XCTAssertEqual(store.annotationUndoTitle, "Undo clear")
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, fixtures + [first, third])
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, fixtures)
    }

    func testMetadataHeightAndTrackingAreIndividualReversibleEdits() throws {
        let store = ReplayStore()
        store.seek(to: 5)
        let mark = try makeMark(store)
        var states = [store.marks]
        XCTAssertTrue(store.updateCoachMarkLabel(id: mark.id, label: "Hold the passing lane"))
        states.append(store.marks)
        XCTAssertTrue(store.setCoachMarkDuration(id: mark.id, duration: 3))
        states.append(store.marks)
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: "navy-dm"))
        states.append(store.marks)
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.5))
        states.append(store.marks)
        XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: 8))
        states.append(store.marks)
        for state in states.dropLast().reversed() {
            XCTAssertEqual(store.annotationUndoTitle, "Undo edit")
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, state)
        }
        for state in states.dropFirst() {
            XCTAssertTrue(store.redoAnnotationEdit())
            XCTAssertEqual(store.marks, state)
        }
    }

    func testJoystickGestureCommitsOneUndoStepAndCancellationCommitsNone() throws {
        let store = ReplayStore()
        let mark = try makeMark(store)
        let baseline = store.marks
        let gesture = UUID()
        for offset in [Float(0.25), 1, 2, 3] {
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: gesture, cumulativeDelta: PitchPoint(x: offset, z: offset)))
        }
        XCTAssertFalse(store.canUndoAnnotationEdit)
        XCTAssertFalse(store.undoAnnotationEdit())
        XCTAssertNotNil(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: gesture))
        let committed = store.marks
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        XCTAssertEqual(store.annotationUndoTitle, "Undo add", "Four samples must create only one edit entry")
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, committed)

        let cancelled = UUID()
        XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .start,
            gestureID: cancelled, cumulativeDelta: PitchPoint(x: -1, z: 1)))
        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: cancelled))
        XCTAssertEqual(store.marks, committed)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline, "Cancellation must not add an intermediate geometry state")
    }

    func testDirectHandlePreviewsAreNotUndoStepsAndCommitIsOneStep() throws {
        let store = ReplayStore()
        let mark = try makeMark(store)
        let before = store.marks
        for offset: Float in [0.5, 1, 1.5] {
            XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
                start: PitchPoint(x: -4 + offset, z: 2), end: PitchPoint(x: 4, z: 10), broadcast: false))
        }
        XCTAssertFalse(store.undoAnnotationEdit())
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.annotationUndoTitle, "Undo add")
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
            start: PitchPoint(x: -2, z: 2), end: PitchPoint(x: 4, z: 10), broadcast: false))
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
            start: PitchPoint(x: -2, z: 2), end: PitchPoint(x: 4, z: 10)))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.annotationUndoTitle, "Undo add")
    }

    func testScrubAndDrawingOwnInputButTransportDoesNotEraseRedo() throws {
        let store = ReplayStore()
        let mark = try makeMark(store)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 13))
        XCTAssertFalse(store.redoAnnotationEdit())
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.commitTimelineScrub(to: 13))
        store.setPlaybackRate(2)
        store.setViewMode(.touchline)
        store.seek(to: 4)
        store.beginDrawing(.run)
        _ = store.registerPitchTap(PitchPoint(x: 1, z: 1))
        XCTAssertFalse(store.redoAnnotationEdit())
        XCTAssertEqual(store.pendingDrawStart, PitchPoint(x: 1, z: 1))
        store.cancelDrawing()
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertTrue(store.marks.contains(mark))
        XCTAssertEqual(store.playhead, 4)
        XCTAssertEqual(store.playbackRate, 2)
        XCTAssertEqual(store.viewMode, .touchline)
    }

    func testNewCommittedEditClearsRedoButRejectedEditsDoNot() throws {
        let store = ReplayStore()
        let first = try makeMark(store)
        _ = try makeMark(store, kind: .run)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertFalse(store.updateCoachMarkLabel(id: first.id, label: ""))
        XCTAssertTrue(store.canRedoAnnotationEdit)
        XCTAssertTrue(store.updateCoachMarkLabel(id: first.id, label: "New decision"))
        XCTAssertFalse(store.canRedoAnnotationEdit)
        XCTAssertFalse(store.redoAnnotationEdit())
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.last, first)
    }

    func testScenarioResetSwitchAndReviewRestoreStartFreshHistoryWithoutLosingMarks() throws {
        let store = ReplayStore()
        let firstScenario = store.selectedScenarioID
        let mark = try makeMark(store)
        XCTAssertTrue(store.saveReview(named: "Before the edit"))
        let review = try XCTUnwrap(store.savedReviews.first)
        store.selectScenario(id: store.scenarios[1].id)
        XCTAssertFalse(store.hasAnnotationEditHistory)
        _ = try makeMark(store)
        store.selectScenario(id: firstScenario)
        XCTAssertTrue(store.marks.contains(mark))
        XCTAssertFalse(store.hasAnnotationEditHistory)
        XCTAssertTrue(store.removeCoachMark(id: mark.id))
        XCTAssertTrue(store.restoreReview(review))
        XCTAssertTrue(store.marks.contains(mark))
        XCTAssertFalse(store.hasAnnotationEditHistory)
        _ = try makeMark(store)
        store.resetScenario()
        XCTAssertEqual(store.marks, store.selectedScenario.coachMarks)
        XCTAssertFalse(store.hasAnnotationEditHistory)
    }

    func testUndoAndRedoCommittedResultsAutosaveButHistoryIsNotSerialized() throws {
        let store = ReplayStore()
        let fixtures = store.marks
        let mark = try makeMark(store)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, fixtures)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, fixtures + [mark])
        let encoded = try JSONEncoder().encode(XCTUnwrap(store.autosavedReview))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).lowercased().contains("undo"))
    }

    func testExternalReplacementCannotBeOverwrittenByOldHistory() throws {
        let store = ReplayStore()
        _ = try makeMark(store)
        let replacement = CoachMark(kind: .pass, start: PitchPoint(x: 0, z: 0),
                                   end: PitchPoint(x: 3, z: 4), label: "External", revealTime: 0)
        store.marks = [replacement]
        XCTAssertFalse(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, [replacement])
        XCTAssertFalse(store.hasAnnotationEditHistory)
    }

    func testHistoryBoundsAndNoOpCommitsPreserveRedo() throws {
        let store = ReplayStore()
        let base = try makeMark(store)
        var history = ReplayAnnotationEditHistory(marks: [])
        var current: [CoachMark] = []
        for index in 0..<80 {
            current.append(CoachMark(kind: base.kind, start: base.start, end: base.end,
                                     label: "Mark \(index)", revealTime: 0))
            history.record(current)
            XCTAssertLessThanOrEqual(history.retainedMarkCount, ReplayAnnotationEditHistory.maximumRetainedMarkValues)
        }
        var undoCount = 0
        while let previous = history.undo(current: current) {
            current = previous
            undoCount += 1
            XCTAssertLessThanOrEqual(history.retainedMarkCount, ReplayAnnotationEditHistory.maximumRetainedMarkValues)
        }
        XCTAssertGreaterThan(undoCount, 0)
        XCTAssertLessThanOrEqual(undoCount, ReplayAnnotationEditHistory.maximumEntries)
        history.record(current)
        XCTAssertTrue(history.canRedo)
        while let next = history.redo(current: current) { current = next }
        XCTAssertEqual(current.count, 80)
        history.reset(to: [])
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.retainedMarkCount, 0)
    }
}
