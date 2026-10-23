import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationCurveAdjustmentControllerTests: XCTestCase {
    func testDragKeepsOneBaselineAndTokenThenCommitsTheFinalSampleOnce() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: -20)))
        let transaction = try XCTUnwrap(controller.transaction)
        XCTAssertEqual(transaction.baseline, mark.resolvedCurve)
        XCTAssertTrue(controller.isEnabled(in: store, markID: mark.id))
        XCTAssertFalse(store.canChangePlaybackView)
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 28, height: -28)))
        XCTAssertEqual(controller.transaction, transaction)
        let preview = try current(mark.id, in: store)
        XCTAssertEqual(preview.resolvedCurve.bend, mark.resolvedCurve.bend + 0.75, accuracy: 0.000_001)
        XCTAssertEqual(preview.resolvedCurve.lift, 0.75)
        XCTAssertEqual(store.makeSavedReviewState().marks, before, "Uncommitted curve stays out of saves")
        XCTAssertTrue(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 36, height: -36)))
        let committed = try current(mark.id, in: store)
        XCTAssertEqual(committed.resolvedCurve.bend, mark.resolvedCurve.bend + 1, accuracy: 0.000_001)
        XCTAssertEqual(committed.resolvedCurve.lift, 1)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        XCTAssertFalse(store.commitCoachMarkCurvePreview(id: mark.id, gestureID: transaction.gestureID))
    }

    func testCancelRestoresCurveAndEndpointsWithoutChangingTheSelectedMoment() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let time = store.playhead
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: -28, height: -20)))
        controller.cancel(in: store)
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.playhead, time)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(controller.isActive)
    }

    func testCancelledGestureCannotRestartFromALateEndCallback() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: -20)))
        controller.cancel(in: store)
        XCTAssertFalse(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 36, height: -36)))
        XCTAssertEqual(store.marks, before)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        // A new pinch still starts normally after the cancelled one ends.
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        XCTAssertTrue(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 28, height: 0)))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
    }

    func testEndAloneAndDuplicateEndCannotOpenAnotherTransaction() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertFalse(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 20, height: -20)))
        XCTAssertEqual(store.marks, before)
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: -20)))
        XCTAssertTrue(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 28, height: -28)))
        let committed = store.marks
        XCTAssertFalse(controller.finish(in: store, markID: mark.id, translation: CGSize(width: 36, height: -36)))
        XCTAssertEqual(store.marks, committed)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before, "One completed drag creates only one Undo entry")
    }

    func testTimelineOwnerBlocksTheWholeAttemptUntilItsPinchEnds() throws {
        let (store, mark) = try makeArc()
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 7))
        XCTAssertFalse(controller.isEnabled(in: store, markID: mark.id))
        XCTAssertFalse(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        XCTAssertEqual(store.playhead, 7)
        XCTAssertTrue(store.commitTimelineScrub(to: 8))
        XCTAssertFalse(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 28, height: 0)))
        controller.cancel(in: store)
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        controller.cancel(in: store)
    }

    func testAnotherPadCannotUseOrCancelAnOwnedCurve() throws {
        let (store, mark) = try makeArc()
        let first = AnnotationCurveAdjustmentController()
        let second = AnnotationCurveAdjustmentController()
        XCTAssertTrue(first.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        let preview = store.marks
        XCTAssertFalse(second.isEnabled(in: store, markID: mark.id))
        XCTAssertFalse(second.preview(in: store, markID: mark.id, translation: CGSize(width: -20, height: 0)))
        second.cancel(in: store)
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(first.isEnabled(in: store, markID: mark.id))
        first.cancel(in: store)
    }

    func testCancelledOldTokenCannotFinishOrRollbackANewerPad() throws {
        let (store, mark) = try makeArc()
        let old = AnnotationCurveAdjustmentController()
        XCTAssertTrue(old.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        let token = try XCTUnwrap(old.transaction).gestureID
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: token))
        let current = AnnotationCurveAdjustmentController()
        XCTAssertTrue(current.preview(in: store, markID: mark.id, translation: CGSize(width: -28, height: -20)))
        let preview = store.marks
        XCTAssertFalse(old.isEnabled(in: store, markID: mark.id))
        XCTAssertFalse(old.finish(in: store, markID: mark.id, translation: CGSize(width: 36, height: 0)))
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(current.isEnabled(in: store, markID: mark.id))
        current.cancel(in: store)
    }

    func testNudgesAreBoundedAtomicAndUnavailableDuringAnotherEdit() throws {
        let (store, mark) = try makeArc()
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertFalse(controller.canNudge(in: store, markID: mark.id, bend: 0, lift: -0.25))
        XCTAssertTrue(controller.nudge(in: store, markID: mark.id, bend: 0.25, lift: 0.25))
        let adjusted = try current(mark.id, in: store)
        XCTAssertEqual(adjusted.resolvedCurve.bend, mark.resolvedCurve.bend + 0.25, accuracy: 0.000_001)
        XCTAssertEqual(adjusted.resolvedCurve.lift, 0.25)
        XCTAssertEqual(adjusted.start, mark.start)
        XCTAssertEqual(adjusted.end, mark.end)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(controller.nudge(in: store, markID: mark.id, bend: 0.25, lift: 0))
        XCTAssertTrue(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
    }

    func testDeadZoneDoesNotCreateATransactionAndInvalidInputRollsBack() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 2, height: 2)))
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(controller.preview(in: store, markID: mark.id, translation: CGSize(width: CGFloat.nan, height: 0)))
        XCTAssertEqual(store.marks, before)
        XCTAssertFalse(controller.isActive)
    }

    func testArcToolAndPadAreWiredWithoutReplacingEndpointControls() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("annotationToolButton(.arc, label: \"Arc\")"))
        XCTAssertTrue(source.contains("annotationEndpointGeometryRow(mark)"))
        XCTAssertTrue(source.contains("if mark.kind == .arc"))
        XCTAssertTrue(source.contains("AnnotationArcPointEditor(markID: mark.id"))
        XCTAssertFalse(source.contains("AnnotationCurveAdjustmentPad(markID: mark.id"))
        let pad = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/AnnotationCurveAdjustmentPad.swift"), encoding: .utf8)
        XCTAssertTrue(pad.contains("controller.finish(in: store, markID: markID, translation: value.translation, mode: mode, fine: fine)"))
        XCTAssertTrue(pad.contains(".onDisappear { controller.cancel(in: store) }"))
        XCTAssertTrue(pad.contains(".onChange(of: markID)"))
        XCTAssertTrue(pad.contains(".onChange(of: dragIsActive)"))
        XCTAssertTrue(pad.contains(".onChange(of: isEnabled)"))
        XCTAssertTrue(pad.contains(".accessibilityAction(named: \"Increase bend\")"))
        XCTAssertTrue(pad.contains(".accessibilityAction(named: \"Lift arc\")"))
        XCTAssertTrue(pad.contains(".accessibilityAction(named: \"Increase curve\")"))
        XCTAssertTrue(pad.contains(".accessibilityAction(named: \"Rotate arc anticlockwise\")"))
        XCTAssertTrue(pad.contains(".disabled(controller.isActive)"))
        XCTAssertTrue(pad.contains(".help(choice == .shape"))
    }

    func testParametricJoystickChangesAmountAndAngleFromOneCapturedBaseline() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id,
            translation: CGSize(width: 20, height: -20), mode: .shape))
        let transaction = try XCTUnwrap(controller.transaction)
        XCTAssertEqual(transaction.mode, .shape)
        XCTAssertTrue(controller.preview(in: store, markID: mark.id,
            translation: CGSize(width: 28, height: -28), mode: .shape))
        let preview = try current(mark.id, in: store)
        XCTAssertEqual(preview.resolvedCurve.amount, mark.resolvedCurve.amount + 0.75, accuracy: 0.000_01)
        XCTAssertEqual(preview.resolvedCurve.rollDegrees, 15)
        XCTAssertEqual(preview.start, mark.start)
        XCTAssertEqual(preview.end, mark.end)
        XCTAssertEqual(store.makeSavedReviewState().marks, before)
        XCTAssertEqual(controller.transaction, transaction)
        XCTAssertTrue(controller.finish(in: store, markID: mark.id,
            translation: CGSize(width: 36, height: -36), mode: .shape))
        XCTAssertEqual(try current(mark.id, in: store).resolvedCurve.rollDegrees, 20)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
    }

    func testModeChangeDuringDragCancelsRatherThanReinterpretingGesture() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id,
            translation: CGSize(width: 20, height: -20), mode: .shape))
        XCTAssertFalse(controller.preview(in: store, markID: mark.id,
            translation: CGSize(width: 28, height: -28), mode: .offset))
        XCTAssertEqual(store.marks, before)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.finish(in: store, markID: mark.id,
            translation: CGSize(width: 28, height: -28), mode: .shape))
        XCTAssertEqual(store.marks, before)
    }

    func testAtomicAngleAndOffsetChangesPreserveEachOtherAndAreOneUndoEach() throws {
        let (store, mark) = try makeArc()
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0, vertical: 30))
        let rotated = try current(mark.id, in: store)
        XCTAssertEqual(rotated.resolvedCurve.rollDegrees, 30)
        XCTAssertEqual(rotated.resolvedCurve.bend, mark.resolvedCurve.bend)
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .offset, horizontal: 0.25, vertical: 0.25))
        let offset = try current(mark.id, in: store)
        XCTAssertEqual(offset.resolvedCurve.rollDegrees, 30)
        XCTAssertEqual(offset.resolvedCurve.bend, rotated.resolvedCurve.bend + 0.25, accuracy: 0.000_01)
        XCTAssertEqual(offset.resolvedCurve.lift, 0.25)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), rotated)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
    }

    func testParametricNudgesRejectNonfiniteInputAndRespectTimelineOwnership() throws {
        let (store, mark) = try makeArc()
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertFalse(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: .nan, vertical: 5))
        XCTAssertFalse(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0, vertical: .infinity))
        XCTAssertEqual(store.marks, before)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
        XCTAssertEqual(store.marks, before)
        store.cancelTimelineScrub()
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0, vertical: 1000))
        XCTAssertEqual(try current(mark.id, in: store).resolvedCurve.rollDegrees, 180)
        XCTAssertFalse(controller.canAdjust(in: store, markID: mark.id, mode: .shape, horizontal: 0, vertical: 5))
    }

    private func makeArc() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertFalse(store.reviewLibrary.usesDisk)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -20, z: -20)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: -16, z: -14)))
        return (store, mark)
    }

    private func current(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }
}
