import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationPresentationCacheTests: XCTestCase {
    func testPausedKeyframedArcSkipsSixtyGeometryUpdates() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], time: 4)
        let entity = try markEntity(mark, in: root)
        let path = try XCTUnwrap(entity.findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
        let mesh = try XCTUnwrap(path.model?.mesh)
        let picker = try XCTUnwrap(entity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        let hitTransforms = picker.children.map(\.transform)

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        for _ in 0..<60 { update(root, scenario: scenario, marks: [mark], time: 4) }

        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.unchangedTrackedGeometrySkips, 60)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.semanticRevisions, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
        XCTAssertTrue(path.model?.mesh === mesh)
        XCTAssertEqual(picker.children.map(\.transform), hitTransforms)
    }

    func testAdvancingTimeWithHeldEndPoseAlsoSkipsGeometry() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], time: 7)
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        for frame in 1...60 {
            update(root, scenario: scenario, marks: [mark], time: 7 + Double(frame) / 30)
        }
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.unchangedTrackedGeometrySkips, 60)
    }

    func testSeekingHiddenIntervalAndBackRestoresActualGeometry() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], time: 0)
        let entity = try markEntity(mark, in: root)
        let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
        let startPose = arrow.position
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [mark], time: 4)
        XCTAssertNotEqual(arrow.position, startPose)
        update(root, scenario: scenario, marks: [mark], time: 6)
        let endPose = arrow.position
        update(root, scenario: scenario, marks: [mark], time: 21)
        XCTAssertFalse(entity.isEnabled)
        XCTAssertEqual(arrow.position, endPose)
        update(root, scenario: scenario, marks: [mark], time: 0)
        XCTAssertTrue(entity.isEnabled)
        XCTAssertEqual(arrow.position, startPose)
        XCTAssertTrue(try markEntity(mark, in: root) === entity)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 3)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
    }

    func testSameTimestampKeyframeEditInvalidatesAppliedGeometry() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], time: 4)
        let entity = try markEntity(mark, in: root)
        let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
        let oldPosition = arrow.position
        var edited = mark
        let newEnd = CoachMark(kind: .arc, start: .init(x: 4, z: 2), end: .init(x: 14, z: 12),
                              curve: .init(bend: 3, lift: 1), label: "Arc")
        edited.keyframes?[1] = CoachMarkKeyframe(time: 6, mark: newEnd)
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [edited], time: 4)
        XCTAssertNotEqual(arrow.position, oldPosition)
        XCTAssertEqual(arrow.position.x, edited.sampled(at: 4).end.x, accuracy: 0.0001)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 1)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 1)
        update(root, scenario: scenario, marks: [edited], time: 4)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.unchangedTrackedGeometrySkips, 1)
        XCTAssertTrue(try markEntity(edited, in: root) === entity)
    }

    func testGeometryCacheDoesNotSuppressSemanticTreeRepair() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], time: 4)
        let original = try markEntity(mark, in: root)
        let removed = try XCTUnwrap(original.findEntity(named: "annotation-mark-arrow"))
        removed.removeFromParent()
        let unrelated = CoachMark(kind: .run, start: .init(x: -20, z: -20), end: .init(x: -18, z: -18),
                                  label: "Other", revealTime: 0)
        update(root, scenario: scenario, marks: [mark, unrelated], time: 4)
        let repaired = try markEntity(mark, in: root)
        XCTAssertFalse(repaired === original)
        let arrow = try XCTUnwrap(repaired.findEntity(named: "annotation-mark-arrow"))
        XCTAssertEqual(arrow.position.x, mark.sampled(at: 4).end.x, accuracy: 0.0001)
        XCTAssertEqual(arrow.position.z, mark.sampled(at: 4).end.z, accuracy: 0.0001)
    }

    func testArcMeshReusesFull3DTranslationButRebuildsForFloorClipping() throws {
        let path = ModelEntity(mesh: .generateSphere(radius: 0.1), materials: [UnlitMaterial(color: .white)])
        func mark(height: Float, roll: Float = 0) -> CoachMark {
            CoachMark(kind: .arc, start: .init(x: -10, z: 0), end: .init(x: 10, z: 0),
                      startElevation: height, endElevation: height,
                      curve: .init(bend: 3, lift: 1, rollDegrees: roll), label: "Arc")
        }
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: mark(height: 0.5)))
        let originalMesh = try XCTUnwrap(path.model?.mesh)
        for frame in 1...30 {
            XCTAssertTrue(AnnotationArcMesh.update(path, mark: mark(height: 0.5 + Float(frame) / 30)))
            XCTAssertTrue(path.model?.mesh === originalMesh)
        }
        XCTAssertEqual(path.position.y, 1, accuracy: 0.0001)
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: mark(height: 0.5)))
        XCTAssertEqual(path.position, .zero)
        XCTAssertTrue(path.model?.mesh === originalMesh)

        XCTAssertTrue(AnnotationArcMesh.update(path, mark: mark(height: 0, roll: -90)))
        let floorMesh = try XCTUnwrap(path.model?.mesh)
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: mark(height: 1, roll: -90)))
        XCTAssertFalse(path.model?.mesh === floorMesh,
                       "Floor-clamped control point did not translate with the endpoints")
        XCTAssertEqual(path.position, .zero)
    }

    private func animatedArc() -> CoachMark {
        let first = CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 8, z: 10),
                              curve: .init(bend: 3, lift: 1), label: "Animated", revealTime: 0, hideTime: 20)
        var last = CoachMark(id: first.id, kind: .arc,
                             start: .init(x: 4, z: 2), end: .init(x: 12, z: 12),
                             curve: first.curve, label: first.label, revealTime: 0, hideTime: 20)
        last.keyframes = [CoachMarkKeyframe(time: 2, mark: first), CoachMarkKeyframe(time: 6, mark: last)]
        return last
    }

    private func markEntity(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
    }

    private func update(_ root: Entity, scenario: ReplayScenario, marks: [CoachMark], time: TimeInterval) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                                 viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                                 marks: marks, showsLaneLens: false, isDrawing: false,
                                 positionalOriginTransform: nil)
    }
}
