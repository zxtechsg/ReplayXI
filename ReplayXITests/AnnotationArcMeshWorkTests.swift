import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationArcMeshWorkTests: XCTestCase {
    func testHoistedArcMathPreservesVerticesNormalsAndTopology() throws {
        let cases: [(PitchPoint, PitchPoint, Float, Float, CoachMarkCurve)] = [
            (.init(x: -8, z: -10), .init(x: 4, z: -4), 0.2, 0.4, .init(bend: 2, lift: 1, rollDegrees: -20)),
            (.init(x: -4, z: -6), .init(x: 8, z: 2), 1, 2, .init(bend: 4, lift: 2, rollDegrees: 80)),
            (.init(x: -10, z: 50), .init(x: 10, z: 50), 0, 0, .init(bend: 8, lift: 0)),
            (.init(x: -10, z: 0), .init(x: 10, z: 0), 0, 0, .init(bend: 8, lift: 2, rollDegrees: -90)),
            (.init(x: -2, z: -3), .init(x: 4, z: 7), 4, 4, .init(bend: 12, lift: 4, rollDegrees: 90)),
            (.zero, .zero, 0, 3, .init(bend: 3, lift: 1, rollDegrees: 45)),
            (.zero, .zero, 1, 1, .init(bend: 0, lift: 0)),
            (.init(x: 34, z: 52.5), .init(x: 34, z: -52.5), 0, 3, .init(bend: -12, lift: 4, rollDegrees: 15))
        ]
        for fixture in cases {
            let mark = CoachMark(kind: .arc, start: fixture.0, end: fixture.1,
                                 startElevation: fixture.2, endElevation: fixture.3,
                                 curve: fixture.4, label: "Fixture")
            AnnotationArcMesh.resetWorkForTesting()
            let mesh = try XCTUnwrap(AnnotationArcMesh.mesh(for: mark, radius: 0.492, baseY: 0.48))
            let model = try XCTUnwrap(mesh.contents.models.first)
            let part = try XCTUnwrap(model.parts.first)
            let vertices = Array(part.positions.elements)
            let normals = Array(try XCTUnwrap(part.normals).elements)
            let expected = referenceGeometry(mark, radius: 0.492, baseY: 0.48)
            XCTAssertEqual(vertices.count, expected.positions.count)
            XCTAssertEqual(normals.count, expected.normals.count)
            XCTAssertEqual(Array(try XCTUnwrap(part.triangleIndices).elements), expected.indices)
            for (actual, wanted) in zip(vertices, expected.positions) { assertVector(actual, wanted) }
            for (actual, wanted) in zip(normals, expected.normals) { assertVector(actual, wanted) }
            XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 1)
            XCTAssertEqual(AnnotationArcMesh.work.controlPointEvaluations, 1)
        }
    }

    func testSelectedPausedArcDoesNotRewriteEitherHighlightTransform() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, mark: mark, time: 4)
        AnnotationArcMesh.resetWorkForTesting()
        for _ in 0..<60 { update(root, scenario: scenario, mark: mark, time: 4) }
        XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 0)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshUpdates, 120,
                       "Only the two selected highlight tubes need admission; base geometry is already cached")
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshTransformWrites, 0)
    }

    func testSelectedArcForwardAndReverseMorphResolvesOneControlPointPerTube() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedArc()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, mark: mark, time: 2)
        let arrow = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
            .findEntity(named: "annotation-mark-arrow"))
        let initial = arrow.transform
        let forward = (1...10).map { 2 + Double($0) / 5 }
        let reverse = (0..<10).reversed().map { 2 + Double($0) / 5 }
        AnnotationArcMesh.resetWorkForTesting()
        for time in forward + reverse { update(root, scenario: scenario, mark: mark, time: time) }
        XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 60,
                       "20 changed samples × base path and two highlight tubes")
        XCTAssertEqual(AnnotationArcMesh.work.controlPointEvaluations, 60)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshUpdates, 0)
        XCTAssertEqual(arrow.transform, initial)
    }

    func testTranslationWritesOnlyWhenPlacementChangesAndRewindIsAbsolute() throws {
        let path = ModelEntity(mesh: .generateBox(size: 0.1), materials: [UnlitMaterial(color: .white)])
        let original = CoachMark(kind: .arc, start: .init(x: -8, z: -10), end: .init(x: 4, z: -4),
                                 curve: .init(bend: 3, lift: 1), label: "Arc")
        let moved = CoachMark(kind: .arc, start: .init(x: -4, z: -8), end: .init(x: 8, z: -2),
                              startElevation: 1, endElevation: 1, curve: original.curve, label: original.label)
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: original))
        let mesh = try XCTUnwrap(path.model?.mesh)
        AnnotationArcMesh.resetWorkForTesting()
        for _ in 0..<30 { XCTAssertTrue(AnnotationArcMesh.update(path, mark: moved)) }
        XCTAssertEqual(path.position, SIMD3<Float>(4, 1, 2))
        for _ in 0..<30 { XCTAssertTrue(AnnotationArcMesh.update(path, mark: original)) }
        XCTAssertEqual(path.position, .zero)
        XCTAssertTrue(path.model?.mesh === mesh)
        XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 0)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshUpdates, 60)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshTransformWrites, 2)
    }

    /// The prior per-ring implementation remains the independent geometric
    /// reference, including finite-difference tangents and clipping behaviour.
    private func referenceGeometry(_ mark: CoachMark, radius: Float, baseY: Float)
        -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        let curve = mark.resolvedCurve
        let steps = CoachMarkCurve.segmentCount
        let sides = 6
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let start = curve.point(at: 0, for: mark)
        let end = curve.point(at: 1, for: mark)
        let plane = simd_cross(curve.controlPoint(for: mark) - start, end - start)
        let planeNormal: SIMD3<Float>? = simd_length_squared(plane) > 0.000001 ? simd_normalize(plane) : nil
        for ring in 0...steps {
            let t = Float(ring) / Float(steps)
            let centre = curve.point(at: t, for: mark, baseY: baseY)
            let delta = curve.point(at: min(1, t + 0.001), for: mark)
                - curve.point(at: max(0, t - 0.001), for: mark)
            let tangent = simd_length_squared(delta) > 0.0000001 ? simd_normalize(delta) : SIMD3<Float>(0, 0, 1)
            let reference = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let side = planeNormal ?? simd_normalize(simd_cross(reference, tangent))
            let up = simd_normalize(simd_cross(tangent, side))
            for corner in 0..<sides {
                let angle = Float(corner) * 2 * .pi / Float(sides)
                let normal = side * cos(angle) + up * sin(angle)
                positions.append(centre + normal * radius)
                normals.append(normal)
            }
            guard ring < steps else { continue }
            for corner in 0..<sides {
                let a = UInt32(ring * sides + corner), b = UInt32(ring * sides + (corner + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let last = UInt32(steps * sides)
        for corner in 1..<(sides - 1) {
            indices.append(contentsOf: [0, UInt32(corner + 1), UInt32(corner),
                                       last, last + UInt32(corner), last + UInt32(corner + 1)])
        }
        return (positions, normals, indices)
    }

    private func animatedArc() -> CoachMark {
        let first = CoachMark(kind: .arc, start: .init(x: -8, z: -10), end: .init(x: 4, z: -4),
                              startElevation: 0.2, endElevation: 0.4,
                              curve: .init(bend: 2, lift: 1, rollDegrees: -20), label: "Morph", revealTime: 0)
        var last = CoachMark(id: first.id, kind: .arc, start: .init(x: -4, z: -6), end: .init(x: 8, z: 2),
                             startElevation: 1, endElevation: 2,
                             curve: .init(bend: 4, lift: 2, rollDegrees: 80), label: first.label, revealTime: 0)
        last.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        return last
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .tacticalTable,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                                 selectedAnnotationID: mark.id, selectedAnnotationIsEditable: true,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.00002, file: file, line: line)
    }
}
