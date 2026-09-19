import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationPositionTimeDraftTests: XCTestCase {
    private var mark: CoachMark {
        CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 5, z: 5),
                  label: "Run", revealTime: 2, hideTime: 10)
    }

    func testSwitchingPositionsCannotDiscardTypedDestination() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2))
        draft.text = "4"
        XCTAssertTrue(draft.isDirty)
        XCTAssertFalse(draft.select(6))
        XCTAssertFalse(draft.select(2), "Tapping the same position must not reset its pending edit")
        XCTAssertEqual(draft.selectedTime, 2)
        XCTAssertEqual(draft.text, "4")
    }

    func testInvalidDraftAlsoBlocksSwitchingUntilExplicitReset() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2))
        draft.text = "1:"
        XCTAssertTrue(draft.isDirty)
        XCTAssertFalse(draft.select(6))
        draft.reset()
        XCTAssertEqual(draft.text, "2")
        XCTAssertFalse(draft.isDirty)
        XCTAssertTrue(draft.select(6))
    }

    func testEquivalentTimestampIsNotAnUnsavedEdit() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2))
        draft.text = "0:02.000"
        XCTAssertFalse(draft.isDirty)
        XCTAssertTrue(draft.select(6))
    }

    func testSuccessfulMoveUpdatesDraftBaselineWithoutRequiringReset() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2))
        draft.text = "0:04.5"
        draft.acceptCommittedTime(4.5)
        XCTAssertEqual(draft.selectedTime, 4.5)
        XCTAssertEqual(draft.text, "4.5")
        XCTAssertFalse(draft.isDirty)
        draft.clear()
        XCTAssertNil(draft.selectedTime)
        XCTAssertEqual(draft.text, "")
    }

    func testPositionAndVisibilityResetsAreIndependent() {
        var window = AnnotationTimingDraft(mark: mark, duration: 20)
        var position = AnnotationPositionTimeDraft()
        XCTAssertTrue(position.select(2))
        window.startText = "3"
        position.text = "4"
        position.reset()
        XCTAssertEqual(window.startText, "3")
        XCTAssertTrue(window.differs(from: mark))
        position.text = "5"
        window = AnnotationTimingDraft(mark: mark, duration: 20)
        XCTAssertEqual(position.text, "5")
        XCTAssertTrue(position.isDirty)
        XCTAssertFalse(window.differs(from: mark))
    }

    func testShapeNavigationRequiresBothDraftsToBeResolved() {
        for windowDirty in [false, true] {
            for positionDirty in [false, true] {
                XCTAssertEqual(AnnotationTimingEditPolicy.canLeaveEditor(windowIsDirty: windowDirty,
                    positionIsDirty: positionDirty), !windowDirty && !positionDirty)
            }
        }
    }

    func testVisibilityCopyDescribesTimeWindowNotSelectedPreviewVisibility() {
        XCTAssertEqual(AnnotationTimingEditPolicy.visibilityLabel(for: mark, at: 1.9), "Outside In/Out")
        XCTAssertEqual(AnnotationTimingEditPolicy.visibilityLabel(for: mark, at: 2), "Inside In/Out")
        XCTAssertEqual(AnnotationTimingEditPolicy.visibilityLabel(for: mark, at: 10), "Outside In/Out")
        XCTAssertTrue(AnnotationTimingEditPolicy.outsideWindowHint.contains("Shown for editing"))
        let throughEnd = CoachMark(kind: mark.kind, start: mark.start, end: mark.end,
            label: mark.label, revealTime: 2, hideTime: nil)
        XCTAssertEqual(AnnotationTimingEditPolicy.visibilityLabel(for: throughEnd, at: 20), "Inside In/Out")
    }

    func testInvalidSelectionDoesNotChangeCurrentDraft() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2))
        for time in [Double.nan, .infinity, -1] {
            XCTAssertFalse(draft.select(time))
            XCTAssertEqual(draft.selectedTime, 2)
        }
    }

    func testDecimalNudgesPreserveSelectedKeyAndReachExactReplayEdges() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(0))
        for _ in 0..<10 { XCTAssertTrue(draft.nudge(by: 0.1, duration: 1)) }
        XCTAssertEqual(draft.text, "1")
        XCTAssertEqual(draft.selectedTime, 0)
        XCTAssertTrue(draft.isDirty)
        XCTAssertNil(draft.nudgedTime(by: 0.1, duration: 1))
        XCTAssertFalse(draft.nudge(by: 0.1, duration: 1))
        for _ in 0..<10 { XCTAssertTrue(draft.nudge(by: -0.1, duration: 1)) }
        XCTAssertEqual(draft.text, "0")
        XCTAssertFalse(draft.isDirty)
        XCTAssertFalse(draft.nudge(by: -0.1, duration: 1))
    }

    func testNudgeUsesTypedDestinationAndPreservesSubframePrecision() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertTrue(draft.select(2.123456))
        draft.text = "0:04.123456"
        XCTAssertTrue(draft.nudge(by: 0.1, duration: 20))
        XCTAssertEqual(draft.text, "4.223456")
        XCTAssertEqual(draft.selectedTime, 2.123456)
        draft.reset()
        XCTAssertEqual(draft.text, "2.123456")
    }

    func testNudgeRejectsInvalidDraftsAndBoundsWithoutReplacingText() {
        var draft = AnnotationPositionTimeDraft()
        XCTAssertFalse(draft.nudge(by: 0.1, duration: 20))
        XCTAssertTrue(draft.select(2))
        for text in ["1:", "nan", "-1", "21", "20", "19.95"] {
            draft.text = text
            let before = draft
            XCTAssertFalse(draft.nudge(by: 0.1, duration: 20), text)
            XCTAssertEqual(draft, before)
        }
        draft.text = "2"
        for (delta, duration) in [(Double.nan, 20.0), (.infinity, 20), (0, 20),
                                  (0.1, Double.nan), (0.1, .infinity), (0.1, -1)] {
            let before = draft
            XCTAssertFalse(draft.nudge(by: delta, duration: duration))
            XCTAssertEqual(draft, before)
        }
    }

    func testKeyTimeValidationExplainsMalformedOutOfBoundsAndOccupiedTime() {
        let keyed = mark.recordingPose(at: 2).recordingPose(at: 4)
        var draft = AnnotationPositionTimeDraft()
        XCTAssertEqual(draft.validationMessage(for: keyed, duration: 20), "Select a saved position.")
        XCTAssertTrue(draft.select(2))
        XCTAssertNil(draft.validationMessage(for: keyed, duration: 20))
        draft.text = "1:"
        XCTAssertEqual(draft.validationMessage(for: keyed, duration: 20), "Use seconds or m:ss, e.g. 12.5 or 1:12.5.")
        draft.text = "21"
        XCTAssertEqual(draft.validationMessage(for: keyed, duration: 20), "Keep the position time inside this replay.")
        for text in ["4", "4.0000005"] {
            draft.text = text
            XCTAssertEqual(draft.validationMessage(for: keyed, duration: 20), "A position is already saved at this time.")
        }
        draft.text = "12"
        XCTAssertNil(draft.validationMessage(for: keyed, duration: 20), "Keys outside In/Out remain valid")
        XCTAssertEqual(draft.validationMessage(for: mark, duration: 20), "Select a saved position.")
    }

    func testNudgesStayDraftOnlyUntilOneUndoableApply() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        let current = try XCTUnwrap(store.marks.first { $0.id == created.id })
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: current, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration, store: store))
        defer { session.releaseOwnership() }
        XCTAssertTrue(session.position.select(2))
        let before = store.makeSavedReviewState()
        let beforeMarks = store.marks
        for _ in 0..<5 { XCTAssertTrue(session.position.nudge(by: 0.1, duration: store.selectedScenario.duration)) }
        XCTAssertEqual(session.position.text, "2.5")
        XCTAssertEqual(store.pendingAnnotationTimingEditID, current.id)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state, before)
        XCTAssertTrue(session.apply(in: store))
        XCTAssertEqual(store.marks.first { $0.id == current.id }?.keyframes?.map(\.time), [2.5])
        XCTAssertEqual(store.playhead, 2, "Draft Apply does not seek")
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, beforeMarks, "Five nudges commit as one edit")
    }

    func testTimingEditorWiresNudgesToDraftOnlyAndExplainsCommit() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/AnnotationTimingEditor.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func positionTimeNudge(")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func adaptiveRow<")?.lowerBound)
        let handler = source[start..<end]
        XCTAssertTrue(handler.contains("positionDraft.nudge(by: delta, duration: duration)"))
        XCTAssertTrue(handler.contains("minimumSpatialHitTarget"))
        XCTAssertTrue(handler.contains("Choose Move to save, or Reset to discard"))
        for mutation in ["store.seek", "store.retime", "store.capture", "session.apply"] {
            XCTAssertFalse(handler.contains(mutation))
        }
        XCTAssertTrue(source.contains("positionDraft.validationMessage(for: mark, duration: duration)"))
    }
}
