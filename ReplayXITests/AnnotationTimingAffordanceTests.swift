import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingAffordanceTests: XCTestCase {
    private var mark: CoachMark {
        CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 5, z: 5),
                  label: "Run", revealTime: 2, hideTime: 10)
    }

    func testStartHereKeepsEndAndSubframePrecision() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 32)
        XCTAssertTrue(draft.setBoundary(.start, at: 3.123456, duration: 32))
        XCTAssertEqual(draft.startText, "3.123456")
        XCTAssertEqual(draft.end, 10)
        XCTAssertEqual(draft.visibleRange(duration: 32), 3.123456...10)
    }

    func testEndHereReplacesThroughEndWithoutChangingStart() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 32)
        draft.throughEnd = true
        XCTAssertEqual(draft.visibleRange(duration: 32), 2...32)
        XCTAssertTrue(draft.setBoundary(.end, at: 8, duration: 32))
        XCTAssertFalse(draft.throughEnd)
        XCTAssertEqual(draft.start, 2)
        XCTAssertEqual(draft.visibleRange(duration: 32), 2...8)
    }

    func testReversedRangeRemainsEditableAndNeverShowsAFalsePreview() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 32)
        XCTAssertTrue(draft.setBoundary(.start, at: 12, duration: 32))
        XCTAssertEqual(draft.end, 10, "Start here must not silently move End")
        XCTAssertNotNil(draft.validationMessage(duration: 32))
        XCTAssertNil(draft.visibleRange(duration: 32))
        XCTAssertTrue(draft.setBoundary(.end, at: 15, duration: 32))
        XCTAssertEqual(draft.visibleRange(duration: 32), 12...15)
    }

    func testUnavailablePlayheadNeverDamagesDraft() {
        let baseline = AnnotationTimingDraft(mark: mark, duration: 32)
        for time in [Double.nan, .infinity, -.infinity, -1, 33] {
            var draft = baseline
            XCTAssertFalse(draft.setBoundary(.start, at: time, duration: 32))
            XCTAssertFalse(draft.setBoundary(.end, at: time, duration: 32))
            XCTAssertEqual(draft, baseline)
        }
        for duration in [Double.nan, .infinity, -1] {
            var draft = baseline
            XCTAssertFalse(draft.setBoundary(.end, at: 8, duration: duration))
            XCTAssertEqual(draft, baseline)
        }
    }

    func testHereActionsStayDraftOnlyUntilOneUndoableSave() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 5, z: 5)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 6)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        let saved = try XCTUnwrap(store.marks.first { $0.id == created.id })
        let before = store.marks
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: saved, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration, store: store))
        defer { session.releaseOwnership() }
        XCTAssertTrue(session.window.setBoundary(.start, at: 1, duration: store.selectedScenario.duration))
        XCTAssertTrue(session.window.setBoundary(.end, at: 9, duration: store.selectedScenario.duration))
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, created.id)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, before)

        XCTAssertTrue(session.apply(in: store))
        let edited = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(edited.revealTime, 1)
        XCTAssertEqual(edited.hideTime, 9)
        XCTAssertEqual(edited.keyframes, saved.keyframes)
        XCTAssertEqual(store.playhead, 6)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, store.marks)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
    }
}
