import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkKeyframeRetimingTests: XCTestCase {
    private func keyedMark() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
            start: .init(x: 4, z: 2), end: .init(x: 12, z: 12)))
        return (store, try XCTUnwrap(store.marks.last))
    }

    func testRetimingPreservesPoseVisibilityAndSingleUndo() throws {
        let (store, mark) = try keyedMark()
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 10))
        let changed = try XCTUnwrap(store.marks.last)
        XCTAssertEqual(changed.keyframes?.map(\.time), [2, 10])
        XCTAssertEqual(changed.sampled(at: 10).start, mark.sampled(at: 6).start)
        XCTAssertEqual(changed.sampled(at: 6).start.x, 2, accuracy: 0.001)
        XCTAssertEqual(changed.revealTime, mark.revealTime)
        XCTAssertEqual(changed.hideTime, mark.hideTime)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.last, changed)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, changed)
    }

    func testRetimingAcrossNeighbourReordersKeysWithoutReplacingPose() throws {
        let (store, mark) = try keyedMark()
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 2, to: 9))
        let changed = try XCTUnwrap(store.marks.last)
        XCTAssertEqual(changed.keyframes?.map(\.time), [6, 9])
        XCTAssertEqual(changed.sampled(at: 9).start, mark.sampled(at: 2).start)
        XCTAssertEqual(changed.sampled(at: 6).start, mark.sampled(at: 6).start)
    }

    func testInvalidOrOccupiedTimesNeverChangeSavedPoses() throws {
        let (store, mark) = try keyedMark()
        let baseline = store.marks
        for destination in [2, 2.0000001, 6, -1, .nan, .infinity, store.selectedScenario.duration + 1] {
            XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: destination))
            XCTAssertEqual(store.marks, baseline)
        }
        XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: .nan, to: 4))
        XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: 3, to: 4))
        XCTAssertFalse(mark.canShiftKeyframes(by: .nan, duration: 20))
        XCTAssertFalse(mark.canShiftKeyframes(by: 1, duration: .nan))
    }

    func testMoveAvailabilityIncludesKeysOutsideVisibilityWindow() throws {
        let (store, mark) = try keyedMark()
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: store.selectedScenario.duration))
        let keyed = try XCTUnwrap(store.marks.last)
        XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(keyed, to: 3, in: store))
        XCTAssertFalse(store.retimeCoachMark(id: keyed.id, to: 3))
        XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(keyed, to: 1, in: store))
        XCTAssertTrue(store.retimeCoachMark(id: keyed.id, to: 1))
    }

    func testGestureOwnersAndUnfinishedDrawingBlockRetiming() throws {
        let (store, mark) = try keyedMark()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 7))
        store.cancelTimelineScrub()
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: token,
            curve: .init(bend: 3, lift: 2, rollDegrees: 40)))
        let preview = store.marks
        XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 7))
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: token))
        store.beginDrawing(.run)
        XCTAssertFalse(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 7))
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: 3))
        store.cancelDrawing()
        XCTAssertEqual(store.marks.last, mark)
    }

    func testFreezeHoldsSampledPoseAndUndoRestoresAllKeys() throws {
        let (store, mark) = try keyedMark()
        store.seek(to: 4)
        XCTAssertTrue(store.freezeCoachMarkKeyframes(id: mark.id))
        let frozen = try XCTUnwrap(store.marks.last)
        XCTAssertNil(frozen.keyframes)
        XCTAssertEqual(frozen.start, mark.sampled(at: 4).start)
        XCTAssertEqual(frozen.end, mark.sampled(at: 4).end)
        XCTAssertEqual(frozen.curve, mark.sampled(at: 4).curve)
        XCTAssertEqual(frozen.revealTime, mark.revealTime)
        XCTAssertEqual(frozen.hideTime, mark.hideTime)
        XCTAssertFalse(store.freezeCoachMarkKeyframes(id: mark.id))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, frozen)
    }
}
