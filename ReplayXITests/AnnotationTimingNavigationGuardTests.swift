import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingNavigationGuardTests: XCTestCase {
    private func fixture() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        return (store, try XCTUnwrap(store.marks.last))
    }

    func testScenarioResetAndReviewRestoreWaitForDraftResolution() throws {
        let (store, mark) = try fixture()
        XCTAssertTrue(store.saveReview(named: "Before draft"))
        let review = try XCTUnwrap(store.savedReviews.first)
        let before = store.makeSavedReviewState()
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        store.selectScenario(id: store.scenarios[1].id)
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 1)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        store.resetScenario()
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 2)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertFalse(store.restoreReview(review))
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 3)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertFalse(store.canRestoreSavedReview)
        // Retapping the active scenario is already a no-op, not a blocked route.
        store.selectScenario(id: store.selectedScenarioID)
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 3)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.canRestoreSavedReview)
        store.selectScenario(id: store.scenarios[1].id)
        XCTAssertEqual(store.selectedScenarioID, store.scenarios[1].id)
        XCTAssertTrue(store.restoreReview(review))
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testDestructiveActionsCannotRemoveTheDraftSourceOrAdvanceHistory() throws {
        let (store, mark) = try fixture()
        let original = store.marks
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(store.undoAnnotationEdit())
        XCTAssertFalse(store.redoAnnotationEdit())
        XCTAssertFalse(store.removeCoachMark(id: mark.id))
        store.clearMarks()
        store.beginDrawing(.pass)
        XCTAssertFalse(store.isDrawing)
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 5)
        XCTAssertEqual(store.marks, original)
        XCTAssertEqual(store.statusMessage, "Apply or discard annotation timing changes first")
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, original)
        XCTAssertTrue(store.removeCoachMark(id: mark.id))
    }

    func testSeekAndApplyStayUsableButNamedSaveCannotOmitPendingTiming() throws {
        let (store, mark) = try fixture()
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(store.canSaveReview)
        XCTAssertEqual(store.reviewSaveBlockReason, "Apply or discard annotation timing changes before saving")
        XCTAssertFalse(store.saveReview(named: "Unapplied"))
        store.seek(to: 6)
        XCTAssertEqual(store.playhead, 6)
        XCTAssertTrue(store.setCoachMarkWindow(id: mark.id, start: 1, end: 9))
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 2, to: 3))
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 0)
        // Lifecycle autosave still saves only committed data, never UI ownership.
        XCTAssertTrue(store.flushReviewAutosave())
        let json = String(decoding: try JSONEncoder().encode(store.makeSavedReviewState()), as: UTF8.self)
        XCTAssertFalse(json.contains("pendingAnnotationTimingEditID"))
        XCTAssertFalse(json.contains("annotationTimingNavigationAttempt"))
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.saveReview(named: "Applied"))
    }

    func testOnlyMatchingOwnerCanClearAndMissingSourceStillAllowsCleanup() throws {
        let (store, mark) = try fixture()
        let other = CoachMark(kind: .run, start: .zero, end: .init(x: 5, z: 5), label: "Other")
        store.marks.append(other)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(store.setAnnotationTimingDraftPending(id: other.id, isPending: true))
        XCTAssertFalse(store.setAnnotationTimingDraftPending(id: other.id, isPending: false))
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
        store.marks.removeAll { $0.id == mark.id } // Simulate forced source replacement.
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertFalse(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        let authored = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        XCTAssertFalse(store.setAnnotationTimingDraftPending(id: authored.id, isPending: true))
    }

    func testPhysicalPlacementCannotReplacePendingTimingEditor() throws {
        let scenario = try XCTUnwrap(DemoScenarios.all.first { $0.kind == .shapeLab })
        let store = ReplayStore(scenarios: [scenario])
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.zero)
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertNotNil(store.trianglePlacementInputBlockReason)
        let before = store.makeSnapshot()
        XCTAssertFalse(store.activateTrianglePlacement(anchorID: UUID()))
        XCTAssertFalse(store.activateLocalTrianglePreview(anchorID: UUID()))
        XCTAssertEqual(store.annotationTimingNavigationAttempt, 2)
        XCTAssertEqual(store.makeSnapshot(), before)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.activateLocalTrianglePreview(anchorID: UUID()))
        store.endTrianglePlacement()
    }

    func testApplyBothDraftsIsOneUndoAndInvalidPairNeverPartiallyApplies() throws {
        let (store, mark) = try fixture()
        let before = store.marks
        let playhead = store.playhead
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        for pair: (Double?, Double?, Double?, Double?) in [
            (1, 9, 2, 1000), (1, 1.1, 2, 3), (nil, 9, nil, nil),
            (1, 9, 2, nil), (1, 9, nil, 3), (.nan, 9, nil, nil),
            (nil, nil, nil, nil)
        ] {
            XCTAssertFalse(store.applyCoachMarkTimingDraft(id: mark.id,
                windowStart: pair.0, windowEnd: pair.1, keyframeFrom: pair.2, keyframeTo: pair.3))
            XCTAssertEqual(store.marks, before)
        }
        XCTAssertTrue(store.applyCoachMarkTimingDraft(id: mark.id,
            windowStart: 1, windowEnd: nil, keyframeFrom: 2, keyframeTo: 3))
        let applied = try XCTUnwrap(store.marks.last)
        XCTAssertEqual(applied.revealTime, 1)
        XCTAssertNil(applied.hideTime)
        XCTAssertEqual(applied.keyframes?.map(\.time), [3])
        XCTAssertEqual(applied.sampled(at: 3).start, mark.sampled(at: 2).start)
        XCTAssertEqual(store.playhead, playhead)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id, "UI owns release after successful Apply")
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, applied)
    }

    func testAtomicApplyHonoursGestureAndAuthoredOverlayGuards() throws {
        let (store, mark) = try fixture()
        let before = store.marks
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(store.applyCoachMarkTimingDraft(id: mark.id,
            windowStart: 1, windowEnd: 9, keyframeFrom: 2, keyframeTo: 3))
        store.cancelTimelineScrub()
        let gesture = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: gesture,
            curve: .init(bend: 2, lift: 1)))
        XCTAssertFalse(store.applyCoachMarkTimingDraft(id: mark.id,
            windowStart: 1, windowEnd: 9, keyframeFrom: 2, keyframeTo: 3))
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: gesture))
        let authored = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        XCTAssertFalse(store.applyCoachMarkTimingDraft(id: authored.id,
            windowStart: 1, windowEnd: 9, keyframeFrom: nil, keyframeTo: nil))
        XCTAssertEqual(store.marks, before)
    }

    func testAtomicApplyCannotWriteAnotherAnnotationsPendingDraft() throws {
        let (store, mark) = try fixture()
        store.beginDrawing(.run)
        _ = store.registerPitchTap(.zero)
        let other = try XCTUnwrap(store.registerPitchTap(.init(x: 4, z: 7)))
        let before = store.marks
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(store.applyCoachMarkTimingDraft(id: other.id,
            windowStart: 1, windowEnd: 9, keyframeFrom: nil, keyframeTo: nil))
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertTrue(store.applyCoachMarkTimingDraft(id: other.id,
            windowStart: 1, windowEnd: 9, keyframeFrom: nil, keyframeTo: nil))
    }
}
