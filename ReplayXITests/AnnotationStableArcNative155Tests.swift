import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationStableArcNative155Tests: XCTestCase {
    func testNativeVerticalAndPoleCrossingTubesFollowIndependentCurve155() throws {
        for x: Float in [-0.01, 0, 0.01] {
            for roll: Float in [-120, 0, 120] {
                let mark = fixture(x: x, roll: roll)
                let mesh = try XCTUnwrap(AnnotationArcMesh.mesh(for: mark))
                let model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
                try assertTube(model, mark: mark, radius: 0.075, baseY: 0.10)
            }
        }
    }

    func testNativeSelectedKeyedArcSeekRewindAndPausedMeshReuse155() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let first = fixture(x: -0.01, roll: -60)
        let last = fixture(x: 0.01, roll: 60)
        var mark = first
        mark.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        XCTAssertTrue(mark.hasValidKeyframes(duration: scenario.duration))
        let root = Entity(), marks = Entity()
        marks.name = "marks-root"
        root.addChild(marks)
        root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
        var initialArrow: Transform?
        var initialPositions: [SIMD3<Float>]?
        for time: Double in [2, 3, 4, 5, 6, 4, 2] {
            update(root, scenario: scenario, mark: mark, time: time)
            let pose = mark.sampled(at: time)
            let parent = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
            let path = try XCTUnwrap(parent.findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
            try assertTube(path, mark: pose, radius: 0.075, baseY: 0.10)
            let scale = AnnotationSceneAffordance.visualScale(for: .tacticalTable)
            let lift = AnnotationSceneAffordance.selectionLift(for: .tacticalTable)
            for (name, radius, height) in [("annotation-selection-rail", 0.12 * scale, lift),
                                          ("annotation-selection-core", 0.038 * scale, lift + 0.015)] {
                let model = try XCTUnwrap(root.findEntity(named: name) as? ModelEntity)
                XCTAssertTrue(model.isEnabled)
                try assertTube(model, mark: pose, radius: radius, baseY: height)
            }
            let arrow = try XCTUnwrap(parent.findEntity(named: "annotation-mark-arrow"))
            let end = SIMD3<Float>(pose.end.x, pose.resolvedEndElevation, pose.end.z)
            XCTAssertTrue(arrow.isEnabled)
            vector(arrow.position, end + SIMD3<Float>(0, 0.12, 0))
            vector(arrow.orientation.act([0, 1, 0]), simd_normalize(end - control(pose)))
            let target = try XCTUnwrap(parent.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
            XCTAssertEqual(target.children.count, 16)
            for (index, segment) in target.children.enumerated() {
                let a = point(pose, fraction: Float(index) / 16, baseY: 0.17)
                let b = point(pose, fraction: Float(index + 1) / 16, baseY: 0.17)
                vector(segment.position, (a + b) / 2)
                vector(segment.orientation.act([0, 0, 1]), simd_normalize(b - a))
                XCTAssertEqual(segment.scale.z, simd_distance(a, b) + 0.12, accuracy: 0.00003)
                XCTAssertNotNil(segment.components[CollisionComponent.self])
                XCTAssertNotNil(segment.components[InputTargetComponent.self])
            }
            for endpoint in ["start", "end"] {
                XCTAssertTrue(try XCTUnwrap(root.findEntity(named:
                    "annotation-target-\(endpoint)-\(mark.id.uuidString)")).isEnabled)
            }
            if time == 2 {
                let points = try positions(path)
                if let initialArrow, let initialPositions {
                    XCTAssertEqual(arrow.transform, initialArrow)
                    XCTAssertEqual(points, initialPositions)
                } else { initialArrow = arrow.transform; initialPositions = points }
            }
        }
        AnnotationArcMesh.resetWorkForTesting()
        for _ in 0..<20 { update(root, scenario: scenario, mark: mark, time: 2) }
        XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 0)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshTransformWrites, 0)
    }

    private func fixture(x: Float, roll: Float) -> CoachMark {
        CoachMark(kind: .arc, start: .zero, end: .init(x: x, z: 0),
                  startElevation: 1, endElevation: 3,
                  curve: .init(bend: 1, lift: 0.25, rollDegrees: roll, bendBearingDegrees: 90),
                  label: "Raised arc", revealTime: 0, hideTime: 8)
    }

    /// Independent Rodrigues rotation, not the production quaternion/control method.
    private func control(_ mark: CoachMark) -> SIMD3<Float> {
        let curve = mark.resolvedCurve
        let a = SIMD3<Float>(mark.start.x, mark.resolvedStartElevation, mark.start.z)
        let b = SIMD3<Float>(mark.end.x, mark.resolvedEndElevation, mark.end.z)
        let bearing = (curve.bendBearingDegrees ?? 90) * .pi / 180
        let offset = SIMD3<Float>(cos(bearing) * 2 * curve.bend, 2 * curve.lift,
                                  sin(bearing) * 2 * curve.bend)
        let axis = simd_normalize(b - a), angle = -curve.rollDegrees * .pi / 180
        let rotated = offset * cos(angle) + simd_cross(axis, offset) * sin(angle)
            + axis * simd_dot(axis, offset) * (1 - cos(angle))
        let raw = (a + b) / 2 + rotated
        return [min(max(raw.x, -34), 34), min(max(raw.y, 0), 12), min(max(raw.z, -52.5), 52.5)]
    }

    private func assertTube(_ model: ModelEntity, mark: CoachMark, radius: Float, baseY: Float) throws {
        let values = try positions(model)
        let part = try XCTUnwrap(model.model?.mesh.contents.models.first?.parts.first)
        let normals = Array(try XCTUnwrap(part.normals).elements)
        XCTAssertEqual(values.count, (CoachMarkCurve.segmentCount + 1) * 6)
        XCTAssertEqual(normals.count, values.count)
        let a = SIMD3<Float>(mark.start.x, mark.resolvedStartElevation, mark.start.z)
        let b = SIMD3<Float>(mark.end.x, mark.resolvedEndElevation, mark.end.z)
        let c = control(mark)
        for ring in 0...CoachMarkCurve.segmentCount {
            let t = Float(ring) / Float(CoachMarkCurve.segmentCount)
            let startWeight = (1 - t) * (1 - t)
            let controlWeight = 2 * (1 - t) * t
            let endWeight = t * t
            let expected: SIMD3<Float> = a * startWeight + c * controlWeight + b * endWeight
                + SIMD3<Float>(0, baseY, 0)
            let points = values[(ring * 6)..<(ring * 6 + 6)]
            vector(points.reduce(.zero, +) / 6, expected)
            for (index, point) in points.enumerated() {
                XCTAssertEqual(simd_distance(point, expected), radius, accuracy: 0.00003)
                let normal = normals[ring * 6 + index]
                XCTAssertTrue(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite)
                XCTAssertEqual(simd_length(normal), 1, accuracy: 0.00003)
            }
        }
    }

    private func point(_ mark: CoachMark, fraction t: Float, baseY: Float) -> SIMD3<Float> {
        let a = SIMD3<Float>(mark.start.x, mark.resolvedStartElevation, mark.start.z)
        let b = SIMD3<Float>(mark.end.x, mark.resolvedEndElevation, mark.end.z)
        let startWeight = (1 - t) * (1 - t)
        let controlWeight = 2 * (1 - t) * t
        let endWeight = t * t
        return a * startWeight + control(mark) * controlWeight + b * endWeight + SIMD3<Float>(0, baseY, 0)
    }

    private func positions(_ model: ModelEntity) throws -> [SIMD3<Float>] {
        let part = try XCTUnwrap(model.model?.mesh.contents.models.first?.parts.first)
        return part.positions.elements.map { model.orientation.act($0 * model.scale) + model.position }
    }

    private func vector(_ a: SIMD3<Float>, _ b: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.00003, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.00003, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 0.00003, file: file, line: line)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID, marks: [mark], selectedAnnotationID: mark.id,
            selectedAnnotationIsEditable: true, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil)
    }
}
