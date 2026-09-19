import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingBoundary150Tests: XCTestCase {
    private let boundaryWindows: [(start: Double, end: Double)] = [(7.7, 8.2), (5.7, 35.7)]

    func testDecimalWindowBoundariesAllowOnlyArithmeticRoundoff() {
        XCTAssertLessThan(8.2 - 7.7, 0.5, "The minimum regression must exercise subtraction roundoff")
        XCTAssertGreaterThan(35.7 - 5.7, 30, "The maximum regression must exercise subtraction roundoff")
        var draft = AnnotationTimingDraft()
        draft.throughEnd = false
        for (start, end, valid) in [
            ("7.7", "8.2", true), ("7.7", "8.199999", false), ("7.7", "8.200001", true),
            ("5.7", "35.7", true), ("5.7", "35.700001", false), ("5.7", "35.699999", true),
            ("89.7", "90.2", true), ("89.7", "90.199999", false),
            ("89.7", "119.7", true), ("89.7", "119.700001", false)
        ] {
            draft.startText = start
            draft.endText = end
            XCTAssertEqual(draft.validationMessage(duration: 120) == nil, valid, "\(start)–\(end)")
            let lower = Double(start)!
            let upper = Double(end)!
            let policyAccepts = CoachMarkTimingPolicy.meetsMinimumEditableDuration(revealTime: lower, hideTime: upper)
                && CoachMarkTimingPolicy.windowFits(revealTime: lower, displayDuration: upper - lower,
                                                   replayDuration: 120)
            XCTAssertEqual(policyAccepts, valid, "Draft and commit policy must agree")
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(CoachMarkTimingPolicy.meetsMinimumEditableDuration(revealTime: 1, hideTime: invalid))
            XCTAssertFalse(CoachMarkTimingPolicy.meetsMinimumEditableDuration(revealTime: invalid, hideTime: 2))
            XCTAssertFalse(CoachMarkTimingPolicy.fitsMaximumDuration(revealTime: 1, displayDuration: invalid))
            XCTAssertFalse(CoachMarkTimingPolicy.fitsMaximumDuration(revealTime: invalid, displayDuration: 1))
        }
        // Keep the existing clip-end arithmetic tolerance separate from the
        // much smaller min/max-duration comparison allowance.
        XCTAssertTrue(CoachMarkTimingPolicy.windowFits(revealTime: 0.2, displayDuration: 0.1,
                                                      replayDuration: 0.3))
    }

    func testDirectBoundaryWindowEditsPreserveExactTimesKeysPersistenceAndOneStepUndo() throws {
        for window in boundaryWindows {
            let (store, mark) = try fixture()
            let baseline = store.marks
            XCTAssertTrue(store.setCoachMarkWindow(id: mark.id, start: window.start, end: window.end))
            try assertCommitted(store, baseline: baseline, mark: mark, window: window)
        }
    }

    func testSessionBoundaryWindowEditsPreserveExactTimesKeysPersistenceAndOneStepUndo() throws {
        for window in boundaryWindows {
            let (store, mark) = try fixture()
            let baseline = store.marks
            let session = AnnotationTimingDraftSession()
            XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                        duration: store.selectedScenario.duration, store: store))
            session.window.startText = AnnotationTimestamp.editable(window.start)
            session.window.endText = AnnotationTimestamp.editable(window.end)
            session.window.throughEnd = false
            XCTAssertTrue(session.position.select(6))
            XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
            XCTAssertTrue(session.canApply(in: store))
            XCTAssertTrue(session.apply(in: store))
            XCTAssertFalse(session.hasUnsavedChanges)
            XCTAssertEqual(session.position.selectedTime, 6)
            XCTAssertNil(store.pendingAnnotationTimingEditID)
            try assertCommitted(store, baseline: baseline, mark: mark, window: window)
            session.releaseOwnership()
        }
    }

    func testOneMicrosecondOutsideBoundsIsRejectedWithoutChangingAnySavedMark() throws {
        for window in [(start: 7.7, end: 8.199999), (start: 5.7, end: 35.700001)] {
            let (store, mark) = try fixture()
            let baseline = store.marks
            XCTAssertFalse(store.setCoachMarkWindow(id: mark.id, start: window.start, end: window.end))
            XCTAssertFalse(store.applyCoachMarkTimingDraft(id: mark.id, windowStart: window.start,
                windowEnd: window.end, keyframeFrom: nil, keyframeTo: nil))
            XCTAssertEqual(store.marks, baseline)
            XCTAssertEqual(store.playhead, 4)

            let session = AnnotationTimingDraftSession()
            XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                        duration: store.selectedScenario.duration, store: store))
            session.window.startText = AnnotationTimestamp.editable(window.start)
            session.window.endText = AnnotationTimestamp.editable(window.end)
            session.window.throughEnd = false
            XCTAssertFalse(session.canApply(in: store))
            XCTAssertFalse(session.apply(in: store))
            XCTAssertEqual(store.marks, baseline)
            session.discard(in: store)
            XCTAssertNil(store.pendingAnnotationTimingEditID)
            session.releaseOwnership()

            // Direct duration input has no endpoint subtraction; retain its
            // existing strict bounds instead of adding an unrelated tolerance.
            XCTAssertFalse(store.setCoachMarkDuration(id: mark.id, duration: 0.499999))
            XCTAssertFalse(store.setCoachMarkDuration(id: mark.id, duration: 30.000001))
            XCTAssertEqual(store.marks, baseline)
        }
    }

    private func assertCommitted(_ store: ReplayStore, baseline: [CoachMark], mark: CoachMark,
                                 window: (start: Double, end: Double)) throws {
        let edited = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(edited.revealTime, window.start)
        XCTAssertEqual(edited.hideTime, window.end)
        XCTAssertEqual(edited.keyframes, mark.keyframes)
        XCTAssertEqual(edited.start, mark.start)
        XCTAssertEqual(edited.end, mark.end)
        XCTAssertEqual(edited.curve, mark.curve)
        XCTAssertEqual(store.playhead, 4)
        XCTAssertTrue(ReplayStore.isValidReviewMark(edited, for: store.selectedScenario))
        XCTAssertEqual(try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(edited)), edited)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.first { $0.id == mark.id }, edited)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline, "One Undo restores the complete pre-window state")
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, edited)
    }

    private func fixture() throws -> (ReplayStore, CoachMark) {
        let base = try XCTUnwrap(DemoScenarios.all.first)
        let scenario = ReplayScenario(id: "annotation-timing-boundary-150", kind: base.kind,
            title: "Timing boundary", strapline: "Test", matchContext: "Synthetic", objective: "Test",
            coachPrompt: "Test", proofPoint: "Test", duration: 120, defaultViewMode: base.defaultViewMode,
            defaultPerspectiveID: base.defaultPerspectiveID, featuredPerspectiveIDs: base.featuredPerspectiveIDs,
            players: base.players, ball: base.ball, moments: [], coachMarks: [], formationTargets: [])
        let store = ReplayStore(scenarios: [scenario])
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id, start: .init(x: 2, z: 1),
                                                    end: .init(x: 10, z: 11)))
        store.seek(to: 4)
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(mark.keyframes?.map(\.time), [2, 6])
        return (store, mark)
    }
}
