import XCTest
import RealityKit
@testable import ReplayXI

@MainActor
final class CoachMarkKeyframeTests: XCTestCase {
    func testRendererSeeksBothWaysWithoutRebuildingMark() throws {
        let store = ReplayStore()
        let mark = try make(store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
            start: .init(x: 4, z: 2), end: .init(x: 12, z: 12)))
        let scenario = store.selectedScenario
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        func update(_ time: Double) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                marks: store.marks, showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil)
        }
        update(2)
        let entity = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
        let initial = arrow.position
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(6)
        XCTAssertNotEqual(arrow.position, initial)
        update(2)
        XCTAssertEqual(arrow.position, initial)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
    }

    func testAngleUsesShortestPathAndRejectsMalformedKeys() throws {
        let store = ReplayStore()
        let original = try make(store)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: original.id, start: original.start, end: original.end,
            curve: .init(bend: 2, lift: 1, rollDegrees: 170)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: original.id))
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: original.id, start: original.start, end: original.end,
            curve: .init(bend: 4, lift: 3, rollDegrees: -170)))
        var mark = try XCTUnwrap(store.marks.last)
        XCTAssertEqual(abs(mark.sampled(at: 4).resolvedCurve.rollDegrees), 180, accuracy: 0.001)
        XCTAssertTrue(mark.hasValidKeyframes(duration: 10))
        mark.keyframes?[1].time = 2
        XCTAssertFalse(mark.hasValidKeyframes(duration: 10))
    }
    private func make(_ store: ReplayStore) throws -> CoachMark {
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        return try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
    }

    func testPoseInterpolationUndoAndPersistence() throws {
        let store = ReplayStore()
        let mark = try make(store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
            start: .init(x: 4, z: 2), end: .init(x: 12, z: 12)))
        let animated = try XCTUnwrap(store.marks.last)
        XCTAssertEqual(animated.keyframes?.map(\.time), [2, 6])
        XCTAssertEqual(animated.sampled(at: 4).start.x, 2, accuracy: 0.001)
        XCTAssertEqual(animated.sampled(at: 0).start.x, 0)
        XCTAssertEqual(animated.sampled(at: 10).start.x, 4)
        XCTAssertEqual(animated.sampled(at: 2).start.x, 0)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.last, animated)
        let decoded = try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(animated))
        XCTAssertEqual(decoded, animated)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.last?.keyframes?.count, 1)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, animated)
    }

    func testWindowTrimAndShiftHaveDifferentKeyBehaviour() throws {
        let store = ReplayStore()
        let mark = try make(store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        XCTAssertTrue(store.setCoachMarkWindow(id: mark.id, start: 1, end: 8))
        XCTAssertEqual(store.marks.last?.keyframes?.first?.time, 2)
        XCTAssertFalse(store.marks.last!.isVisible(at: 0.9))
        XCTAssertTrue(store.marks.last!.isVisible(at: 1))
        XCTAssertFalse(store.marks.last!.isVisible(at: 8))
        XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: 3))
        XCTAssertEqual(store.marks.last?.keyframes?.first?.time, 4)
        XCTAssertEqual(store.marks.last?.hideTime, 10)
        XCTAssertFalse(store.setCoachMarkWindow(id: mark.id, start: 4, end: 3))
        XCTAssertFalse(store.setCoachMarkWindow(id: mark.id, start: .nan, end: nil))
    }

    func testCurvePreviewCancellationRestoresAllKeys() throws {
        let store = ReplayStore()
        let mark = try make(store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        store.seek(to: 6)
        let baseline = store.marks
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: token,
            curve: .init(bend: 3, lift: 2, rollDegrees: 45)))
        XCTAssertEqual(store.marks.last?.keyframes?.count, 2)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, baseline)
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: token))
        XCTAssertEqual(store.marks, baseline)
    }

    func testRemoveLastKeyFreezesPoseAndResizePreservesAnchor() throws {
        let store = ReplayStore()
        let mark = try make(store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        XCTAssertTrue(store.removeCoachMarkKeyframe(id: mark.id, at: 2))
        XCTAssertNil(store.marks.last?.keyframes)
        let layout = PlaybackControlDeckLayout.resolve(preset: .standard, usesAccessibilityText: false)
        let large = layout.resized(by: 1.5)
        XCTAssertEqual(large.uniformScale, layout.uniformScale * 1.5)
        XCTAssertEqual(large.forwardOffset, layout.forwardOffset)
        XCTAssertEqual(large.verticalOffset, layout.verticalOffset)
        XCTAssertEqual(large.attachmentWidth, layout.attachmentWidth)
        XCTAssertEqual(layout.resized(by: .nan), layout)
    }
}
