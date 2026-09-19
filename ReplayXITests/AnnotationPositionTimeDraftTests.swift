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
}
