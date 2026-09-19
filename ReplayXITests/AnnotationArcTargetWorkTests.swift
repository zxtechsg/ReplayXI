import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationArcTargetWorkTests: XCTestCase {
    private struct Phase: Codable {
        let name: String
        let samples: Int
        let work: AnnotationSceneAffordance.ArcTargetWork
    }

    private struct Report: Codable {
        let phases: [Phase]
        let qualification: String
    }

    func testPausedAndForwardReverseKeyframesCaptureArcTargetSamplingWork() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = annotationRoot()
        update(root, scenario: scenario, mark: mark, time: 2)
        let target = try bodyTarget(mark, in: root)
        let originalTransforms = target.children.map(\.transform)
        AnnotationSceneAffordance.resetArcTargetWorkForTesting()
        for _ in 0..<60 { update(root, scenario: scenario, mark: mark, time: 2) }
        let paused = AnnotationSceneAffordance.arcTargetWork
        XCTAssertEqual(paused, .init(), "The existing held-geometry guard must still skip body targets")
        XCTAssertEqual(target.children.map(\.transform), originalTransforms)

        let forward: [TimeInterval] = (1...30).map { 2.0 + Double($0) / 15.0 }
        let reverse: [TimeInterval] = (0..<30).reversed().map { 2.0 + Double($0) / 15.0 }
        let times = forward + reverse
        AnnotationSceneAffordance.resetArcTargetWorkForTesting()
        for time in times {
            update(root, scenario: scenario, mark: mark, time: time)
            XCTAssertTrue(try bodyTarget(mark, in: root) === target)
            assertTarget(target, matches: mark.sampled(at: time))
        }
        let moving = AnnotationSceneAffordance.arcTargetWork
        XCTAssertEqual(moving.updates, times.count)
        XCTAssertEqual(moving.controlPointResolutions, times.count)
        XCTAssertEqual(moving.sampledPoints, times.count * 17)
        XCTAssertEqual(target.children.map(\.transform), originalTransforms)
        let report = Report(phases: [
            Phase(name: "60_paused_updates", samples: 60, work: paused),
            Phase(name: "60_forward_reverse_updates", samples: times.count, work: moving)
        ], qualification: "DEBUG explicit arc body-target control-point resolutions and sampled points. Each target has 16 segments. Not allocation counts, internal engine work, CPU time or headset FPS. Every transform is checked against the independent per-segment CoachMarkCurve.point method.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ArcTargetSamplingWork.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testArcTargetsMatchIndependentSamplesAtBoundsAndDegenerateEndpoints() {
        let cases: [(PitchPoint, PitchPoint, Float, Float, CoachMarkCurve)] = [
            (.init(x: -8, z: -10), .init(x: 4, z: -4), 0.2, 0.4, .init(bend: 2, lift: 1, rollDegrees: -20)),
            (.init(x: -4, z: -6), .init(x: 8, z: 2), 1, 2, .init(bend: 4, lift: 2, rollDegrees: 80)),
            (.init(x: -10, z: 50), .init(x: 10, z: 50), 0, 0, .init(bend: 8, lift: 0)),
            (.init(x: -10, z: 0), .init(x: 10, z: 0), 0, 0, .init(bend: 8, lift: 2, rollDegrees: -90)),
            (.init(x: -2, z: -3), .init(x: 4, z: 7), 4, 4, .init(bend: 12, lift: 4, rollDegrees: 90)),
            (.zero, .zero, 0, 3, .init(bend: 3, lift: 1, rollDegrees: 45)),
            (.zero, .zero, 1, 1, .init(bend: 0, lift: 0)),
            (.zero, .init(x: 0.0001, z: 0), 0, 0, .init(bend: 0, lift: 0)),
            (.init(x: 34, z: 52.5), .init(x: 34, z: -52.5), 0, 3, .init(bend: -12, lift: 4, rollDegrees: 15))
        ]
        for item in cases {
            let mark = CoachMark(kind: .arc, start: item.0, end: item.1,
                                 startElevation: item.2, endElevation: item.3,
                                 curve: item.4, label: "Bounds")
            AnnotationSceneAffordance.resetArcTargetWorkForTesting()
            let target = AnnotationSceneAffordance.makeBodyTarget(for: mark)
            assertTarget(target, matches: mark)
            XCTAssertEqual(AnnotationSceneAffordance.arcTargetWork.updates, 1)
            XCTAssertEqual(AnnotationSceneAffordance.arcTargetWork.controlPointResolutions, 1)
            XCTAssertEqual(AnnotationSceneAffordance.arcTargetWork.sampledPoints, 17)
        }
    }

    func testSameTimestampEditsHideRevealAndSeekingRefreshHitVolumes() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var mark = animatedArc()
        let root = annotationRoot()
        update(root, scenario: scenario, mark: mark, time: 4)
        let target = try bodyTarget(mark, in: root)
        let initial = target.children.map(\.transform)
        let revised = CoachMark(kind: .arc, start: .init(x: 24, z: 46), end: .init(x: 32, z: 51),
                                startElevation: 3, endElevation: 1,
                                curve: .init(bend: -10, lift: 3, rollDegrees: -75), label: mark.label)
        mark.keyframes?[1] = .init(time: 6, mark: revised)
        update(root, scenario: scenario, mark: mark, time: 4)
        XCTAssertNotEqual(target.children.map(\.transform), initial)
        assertTarget(target, matches: mark.sampled(at: 4))
        let beforeHidden = target.children.map(\.transform)
        update(root, scenario: scenario, mark: mark, time: 21)
        XCTAssertFalse(try XCTUnwrap(target.parent).isEnabled)
        XCTAssertEqual(target.children.map(\.transform), beforeHidden)
        update(root, scenario: scenario, mark: mark, time: 2)
        XCTAssertTrue(try XCTUnwrap(target.parent).isEnabled)
        assertTarget(target, matches: mark.sampled(at: 2))
        update(root, scenario: scenario, mark: mark, time: 6)
        assertTarget(target, matches: mark.sampled(at: 6))
        XCTAssertTrue(try bodyTarget(mark, in: root) === target)
    }

    func testReconfiguringMutatedAndClonedTargetsRepairsActualTransforms() {
        let mark = animatedArc().sampled(at: 4)
        let parent = Entity()
        let original = AnnotationSceneAffordance.makeBodyTarget(for: mark)
        parent.addChild(original)
        let expected = original.children.map(\.transform)
        let clone = original.clone(recursive: true)
        original.removeFromParent()
        parent.addChild(clone)
        perturb(clone)
        AnnotationSceneAffordance.configureBodyTarget(clone, for: mark, labelPosition: nil)
        assertTarget(clone, matches: mark)
        XCTAssertEqual(clone.children.map(\.transform), expected)
        XCTAssertEqual(original.children.map(\.transform), expected)
        clone.removeFromParent()
        perturb(clone)
        AnnotationSceneAffordance.configureBodyTarget(clone, for: mark, labelPosition: nil)
        assertTarget(clone, matches: mark)
        XCTAssertEqual(clone.children.map(\.transform), expected)
    }

    private func assertTarget(_ target: Entity, matches mark: CoachMark,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(target.transform, .identity, file: file, line: line)
        XCTAssertEqual(target.children.count, 16, file: file, line: line)
        for (index, segment) in target.children.enumerated() {
            // Preserve the old independent per-segment sampling as an oracle.
            let a = mark.resolvedCurve.point(at: Float(index) / 16, for: mark, baseY: 0.17)
            let b = mark.resolvedCurve.point(at: Float(index + 1) / 16, for: mark, baseY: 0.17)
            let direction = b - a
            let length = simd_length(direction)
            let expectedFacing = length > 0.0001 ? direction / length : SIMD3<Float>(0, 0, 1)
            assertVector(segment.position, (a + b) / 2, file: file, line: line)
            assertVector(segment.scale, [1, 1, max(length + 0.12, 0.12)], file: file, line: line)
            assertVector(segment.orientation.act([0, 0, 1]), expectedFacing, file: file, line: line)
            XCTAssertTrue(segment.orientation.vector.x.isFinite, file: file, line: line)
            XCTAssertTrue(segment.orientation.vector.y.isFinite, file: file, line: line)
            XCTAssertTrue(segment.orientation.vector.z.isFinite, file: file, line: line)
            XCTAssertTrue(segment.orientation.vector.w.isFinite, file: file, line: line)
            XCTAssertEqual(simd_length(segment.orientation.vector), 1, accuracy: 0.00002,
                           file: file, line: line)
        }
    }

    private func perturb(_ target: Entity) {
        target.transform = Transform(scale: [2, 3, 4], rotation: simd_quatf(angle: 0.3, axis: [1, 0, 0]),
                                     translation: [10, 9, 8])
        for child in target.children {
            child.transform = Transform(scale: [3, 2, 1], rotation: simd_quatf(angle: 0.7, axis: [0, 1, 0]),
                                        translation: [-10, -20, -30])
        }
    }

    private func annotationRoot() -> Entity {
        // Exercise the real scene sync/admission path without athlete assets,
        // pitch geometry or a native physics bake in this focused fixture.
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        root.addChild(marks)
        return root
    }

    private func animatedArc() -> CoachMark {
        let first = CoachMark(kind: .arc, start: .init(x: -8, z: -10), end: .init(x: 4, z: -4),
                              startElevation: 0.2, endElevation: 0.4,
                              curve: .init(bend: 2, lift: 1, rollDegrees: -20),
                              label: "Morph", revealTime: 0, hideTime: 20)
        var last = CoachMark(id: first.id, kind: .arc, start: .init(x: -4, z: -6), end: .init(x: 8, z: 2),
                             startElevation: 1, endElevation: 2,
                             curve: .init(bend: 4, lift: 2, rollDegrees: 80),
                             label: first.label, revealTime: 0, hideTime: 20)
        last.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        return last
    }

    private func bodyTarget(_ mark: CoachMark, in root: Entity) throws -> Entity {
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        return try XCTUnwrap(markRoot.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                                 viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                                 marks: [mark], showsLaneLens: false, isDrawing: false,
                                 positionalOriginTransform: nil)
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.00002, file: file, line: line)
    }
}
