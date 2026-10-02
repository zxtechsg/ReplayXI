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
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 0,
                       "The saved base pose must not be applied before the sampled edit")
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 1)
        update(root, scenario: scenario, marks: [edited], time: 4)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.unchangedTrackedGeometrySkips, 1)
        update(root, scenario: scenario, marks: [edited], time: 6)
        XCTAssertEqual(arrow.position.x, edited.sampled(at: 6).end.x, accuracy: 0.0001)
        update(root, scenario: scenario, marks: [edited], time: 2)
        XCTAssertEqual(arrow.position.x, edited.sampled(at: 2).end.x, accuracy: 0.0001)
        XCTAssertTrue(try markEntity(edited, in: root) === entity)
    }

    func testRemovingAnimationAppliesStaticGeometryOnTheSameFrame() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let animated = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [animated], time: 4)
        let entity = try markEntity(animated, in: root)
        let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
        let staticMark = CoachMark(id: animated.id, kind: .arc,
                                   start: .init(x: 2, z: 0), end: .init(x: 15, z: 10),
                                   curve: animated.curve, label: animated.label,
                                   revealTime: 0, hideTime: 20)

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [staticMark], time: 4)

        XCTAssertTrue(try markEntity(staticMark, in: root) === entity)
        XCTAssertEqual(arrow.position.x, staticMark.end.x, accuracy: 0.0001)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 1)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 0)
    }

    func testStaticMarkBecomesKeyframedAtCurrentTimeWithMatchingHitTarget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let original = CoachMark(kind: .run, start: .init(x: 0, z: 0),
                                 end: .init(x: 2, z: 2), label: "Run", revealTime: 0)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [original], time: 4)
        let entity = try markEntity(original, in: root)
        let picker = try XCTUnwrap(entity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        let originalPicker = picker.transform

        let later = CoachMark(kind: .run, start: .init(x: 4, z: 2),
                              end: .init(x: 10, z: 6), label: "Run")
        var keyed = CoachMark(id: original.id, kind: .run,
                              start: original.start, end: .init(x: 8, z: 8),
                              label: original.label, revealTime: 0)
        keyed.keyframes = [CoachMarkKeyframe(time: 2, mark: original),
                           CoachMarkKeyframe(time: 6, mark: later)]

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [keyed], time: 4)

        XCTAssertTrue(try markEntity(keyed, in: root) === entity)
        XCTAssertNotEqual(picker.transform, originalPicker)
        try assertRunGeometry(keyed, in: root, expected: keyed.sampled(at: 4))
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 1)
    }

    func testTrackedAnchorEditsAcrossTeamsAndHiddenReverseSeekUpdateHitTarget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let id = UUID()
        func tracked(to player: PlayerTrack, startOffset: PitchPoint) -> CoachMark {
            CoachMark(id: id, kind: .run, start: .init(x: 0, z: 0),
                      end: .init(x: 3, z: 4), label: "Tracked run",
                      revealTime: 5, hideTime: 15,
                      startTrackAnchor: CoachMarkTrackAnchor(
                          playerID: player.id, offset: startOffset
                      ),
                      endTrackAnchor: CoachMarkTrackAnchor(
                          playerID: player.id, offset: .init(x: 3, z: 4)
                      ))
        }
        let first = tracked(to: home, startOffset: .zero)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [first], time: 12)
        let entity = try markEntity(first, in: root)
        let rail = try XCTUnwrap(entity.findEntity(named: "annotation-mark-segment-0"))
        let picker = try XCTUnwrap(entity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        try assertRunGeometry(first, in: root,
                              expected: first.resolvingTrackGeometry(in: scenario, at: 12))

        let awayEdit = tracked(to: away, startOffset: .init(x: -2, z: 1))
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [awayEdit], time: 12)
        XCTAssertTrue(try markEntity(awayEdit, in: root) === entity)
        let awayPose = away.presentationPose(at: 12).position
        let awayPresentation = awayEdit.resolvingTrackGeometry(in: scenario, at: 12)
        XCTAssertEqual(awayPresentation.start.x, awayPose.x - 2, accuracy: 0.0001)
        XCTAssertEqual(awayPresentation.end.z, awayPose.z + 4, accuracy: 0.0001)
        try assertRunGeometry(awayEdit, in: root, expected: awayPresentation)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 1)

        update(root, scenario: scenario, marks: [awayEdit], time: 20)
        XCTAssertFalse(entity.isEnabled)
        let hiddenRail = rail.transform
        let hiddenPicker = picker.transform
        let homeEdit = tracked(to: home, startOffset: .init(x: 1, z: -1))
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: [homeEdit], time: 20)
        XCTAssertFalse(entity.isEnabled)
        XCTAssertEqual(rail.transform, hiddenRail)
        XCTAssertEqual(picker.transform, hiddenPicker)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.revisionGeometryUpdates, 0)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 0)

        update(root, scenario: scenario, marks: [homeEdit], time: 8)
        XCTAssertTrue(entity.isEnabled)
        let homePose = home.presentationPose(at: 8).position
        let homePresentation = homeEdit.resolvingTrackGeometry(in: scenario, at: 8)
        XCTAssertEqual(homePresentation.start.x, homePose.x + 1, accuracy: 0.0001)
        XCTAssertEqual(homePresentation.end.z, homePose.z + 4, accuracy: 0.0001)
        try assertRunGeometry(homeEdit, in: root, expected: homePresentation)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.trackedGeometryUpdates, 1)
        XCTAssertTrue(try markEntity(homeEdit, in: root) === entity)
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

    private func assertRunGeometry(_ mark: CoachMark, in root: Entity,
                                   expected: CoachMark) throws {
        let entity = try markEntity(mark, in: root)
        let rail = try XCTUnwrap(entity.findEntity(named: "annotation-mark-segment-0"))
        let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
        let picker = try XCTUnwrap(entity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        let centerX = (expected.start.x + expected.end.x) / 2
        let centerZ = (expected.start.z + expected.end.z) / 2
        let length = hypot(expected.end.x - expected.start.x,
                           expected.end.z - expected.start.z)
        XCTAssertEqual(rail.position.x, centerX, accuracy: 0.0001)
        XCTAssertEqual(rail.position.z, centerZ, accuracy: 0.0001)
        XCTAssertEqual(arrow.position.x, expected.end.x, accuracy: 0.0001)
        XCTAssertEqual(arrow.position.z, expected.end.z, accuracy: 0.0001)
        XCTAssertEqual(picker.position.x, centerX, accuracy: 0.0001)
        XCTAssertEqual(picker.position.z, centerZ, accuracy: 0.0001)
        XCTAssertEqual(picker.scale.z, length + 0.65, accuracy: 0.0001)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, marks: [CoachMark], time: TimeInterval) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                                 viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                                 marks: marks, showsLaneLens: false, isDrawing: false,
                                 positionalOriginTransform: nil)
    }
}
