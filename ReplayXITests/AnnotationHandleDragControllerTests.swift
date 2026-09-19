import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationHandleDragControllerTests: XCTestCase {
    func testOldTokenOrOlderNilTokenEndCannotConsumeReplacement() throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), a = UUID(), b = UUID()
        XCTAssertTrue(controller.preview(sample(a, mark, source, time: 1), point: point(1), in: store))
        XCTAssertTrue(controller.cancel(in: store, gestureID: a))
        XCTAssertTrue(controller.preview(sample(b, mark, source, time: 4), point: point(2), in: store))
        let replacement = store.marks
        XCTAssertFalse(controller.finish(sample(a, mark, source, time: 5), point: point(5), in: store))
        XCTAssertFalse(controller.finish(sample(nil, mark, source, time: 2), point: point(5), in: store))
        XCTAssertFalse(controller.preview(sample(a, mark, source, time: 6), point: point(5), in: store))
        XCTAssertFalse(controller.cancel(in: store, gestureID: a))
        XCTAssertEqual(store.marks, replacement)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: b))
        XCTAssertTrue(controller.finish(sample(b, mark, source, time: 7), point: point(3), in: store))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.end, point(3))
    }

    func testForeignSourceOppositeEndpointAndChangedStartCannotCancelCurrentHandle() throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), foreign = NSObject(), id = UUID()
        XCTAssertTrue(controller.preview(sample(id, mark, source, time: 3), point: point(1), in: store))
        let before = store.marks
        for event in [sample(id, mark, foreign, time: 4),
                      sample(id, mark, source, time: 4, role: .start),
                      sample(nil, mark, source, time: 4, start: SIMD3(1, 0, 0)),
                      sample(nil, mark, source, time: 2)] {
            XCTAssertFalse(controller.finish(event, point: nil, in: store))
            XCTAssertEqual(store.marks, before)
            XCTAssertEqual(controller.gestureID, id)
            XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: id))
        }
        XCTAssertTrue(controller.cancel(in: store, gestureID: id))
    }

    func testGestureStateResetBeforeValidEndStillCommitsFinalCoordinates() async throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), id = UUID()
        XCTAssertTrue(controller.preview(sample(id, mark, source, time: 1), point: point(1), in: store))
        controller.scheduleInterruptedCleanup(in: store, gestureID: id)
        XCTAssertTrue(controller.finish(sample(nil, mark, source, time: 2), point: point(3), in: store))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.end, point(3))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertNil(controller.target)
        XCTAssertFalse(controller.finish(sample(nil, mark, source, time: 2), point: point(4), in: store))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testMissingEndRollsBackAndRetiresPhysicalGesture() async throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), id = UUID()
        XCTAssertTrue(controller.preview(sample(id, mark, source, time: 1), point: point(1), in: store))
        controller.scheduleInterruptedCleanup(in: store, gestureID: id)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(controller.preview(sample(id, mark, source, time: 2), point: point(2), in: store))
        XCTAssertFalse(controller.finish(sample(id, mark, source, time: 3), point: point(3), in: store))
    }

    func testAuthoritativeCancelAllowsFreshBAndDeferredACleanupCannotTouchIt() async throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), a = UUID(), b = UUID()
        XCTAssertTrue(controller.preview(sample(a, mark, source, time: 1), point: point(1), in: store))
        controller.scheduleInterruptedCleanup(in: store, gestureID: a)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertTrue(controller.preview(sample(b, mark, source, time: 3), point: point(2), in: store))
        let replacement = store.marks
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.marks, replacement)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: b))
        XCTAssertFalse(controller.preview(sample(a, mark, source, time: 4), point: point(4), in: store))
        XCTAssertTrue(controller.finish(sample(b, mark, source, time: 5), point: point(3), in: store))
    }

    func testLostOwnerCleanupCannotCancelAnotherControllersReplacement() throws {
        let (store, mark, old) = try fixture()
        let source = NSObject(), a = UUID(), b = UUID()
        XCTAssertTrue(old.preview(sample(a, mark, source, time: 1), point: point(1), in: store))
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        let current = AnnotationHandleDragController()
        XCTAssertTrue(current.preview(sample(b, mark, source, time: 3), point: point(2), in: store))
        let replacement = store.marks
        old.cancelCurrent(in: store)
        XCTAssertFalse(old.finish(sample(a, mark, source, time: 4), point: point(4), in: store))
        XCTAssertEqual(store.marks, replacement)
        XCTAssertTrue(current.finish(sample(b, mark, source, time: 5), point: point(3), in: store))
    }

    func testInvalidPreviewCanRecoverButMatchingMissingFinalCancels() throws {
        let (store, mark, controller) = try fixture()
        let source = NSObject(), id = UUID()
        XCTAssertFalse(controller.preview(sample(id, mark, source, time: 1), point: mark.start, in: store))
        XCTAssertTrue(controller.preview(sample(id, mark, source, time: 2), point: point(1), in: store))
        XCTAssertFalse(controller.preview(sample(id, mark, source, time: 3), point: mark.start, in: store))
        XCTAssertTrue(controller.preview(sample(id, mark, source, time: 4), point: point(2), in: store))
        XCTAssertFalse(controller.finish(sample(id, mark, source, time: 5), point: nil, in: store))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
    }

    func testWorldCallbacksUseTokenControllerAndResetCleanupCapturesOldID() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func handleAnnotationDragChanged(")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func handleAnnotationStrokeChanged(")?.lowerBound)
        let direct = String(source[start..<end])
        XCTAssertTrue(direct.contains("annotationHandleDrag.preview("))
        XCTAssertTrue(direct.contains("annotationHandleDrag.finish("))
        XCTAssertFalse(direct.contains("store.updateCoachMarkGeometry("))
        XCTAssertFalse(direct.contains("store.commitCoachMarkGeometryPreview("))
        XCTAssertFalse(direct.contains("store.cancelCoachMarkGeometryPreview("))
        XCTAssertTrue(direct.contains("guard showsPlaybackAnnotations"))
        XCTAssertTrue(direct.contains("sourceID: ObjectIdentifier(value.entity)"))
        XCTAssertTrue(direct.contains("value.gestureValue.time"))
        XCTAssertTrue(source.contains("scheduleInterruptedCleanup(in: store, gestureID: oldID)"))
        XCTAssertTrue(source.contains("cancelInterruptedSpatialInteraction(includingHandle: false)"))

        let completionStart = try XCTUnwrap(source.range(of: "private func handleSpatialDragEnded(")?.lowerBound)
        let completion = source[completionStart...]
        let deniedStart = try XCTUnwrap(completion.range(of: "guard acceptsMatchInteraction else")?.lowerBound)
        let deniedEnd = try XCTUnwrap(completion.range(of: "if draggedAnnotationTarget != nil")?.lowerBound)
        let denied = completion[deniedStart..<deniedEnd]
        XCTAssertTrue(denied.contains("handleInputSample(value, target: target), point: nil"))
        XCTAssertFalse(denied.contains("cancelCurrent"), "Rejected native events must not cancel a replacement owner")
    }

    private func sample(_ id: UUID?, _ mark: CoachMark, _ source: NSObject, time: Double,
                        role: AnnotationSceneTargetRole = .end,
                        start: SIMD3<Double> = SIMD3(0, 0, 0)) -> AnnotationHandleInputSample {
        .init(gestureID: id, target: .init(markID: mark.id, role: role),
              sourceID: ObjectIdentifier(source), startLocation: start,
              time: Date(timeIntervalSinceReferenceDate: time))
    }

    private func fixture() throws -> (ReplayStore, CoachMark, AnnotationHandleDragController) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        return (store, mark, AnnotationHandleDragController())
    }

    private func point(_ offset: Float) -> PitchPoint { .init(x: -16 + offset, z: -14 + offset) }
}
