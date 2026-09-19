import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationArcClippingReuseTests: XCTestCase {
    private struct Geometry: Equatable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
    }

    private struct Report: Codable {
        let samples: Int
        let meshBuilds: Int
        let meshReplacements: Int
        let controlPointEvaluations: Int
        let reusedMeshUpdates: Int
        let reusedMeshTransformWrites: Int
        let qualification: String
    }

    func testSelectedClippedArcCapturesRedundantBuildsWithUnchangedVerticesAndNormals() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedClippedArc()
        XCTAssertTrue(mark.hasValidKeyframes(duration: scenario.duration))
        let root = annotationRoot()
        update(root, scenario: scenario, mark: mark, time: 2)
        let models = try arcModels(mark, in: root)
        let original = try models.map { try geometry(of: $0) }
        var previousMeshes = try models.map { try XCTUnwrap($0.model?.mesh) }
        let forward: [TimeInterval] = (1...30).map { 2.0 + Double($0) * 4.0 / 30.0 }
        let reverse: [TimeInterval] = (0..<30).reversed().map { 2.0 + Double($0) * 4.0 / 30.0 }
        let times = forward + reverse
        var replacements = 0
        AnnotationArcMesh.resetWorkForTesting()
        for time in times {
            update(root, scenario: scenario, mark: mark, time: time)
            let sampled = mark.sampled(at: time)
            XCTAssertEqual(sampled.resolvedCurve.controlPoint(for: sampled), SIMD3<Float>(-34, 0, 0))
            for (index, model) in models.enumerated() {
                let mesh = try XCTUnwrap(model.model?.mesh)
                if mesh !== previousMeshes[index] { replacements += 1 }
                previousMeshes[index] = mesh
                XCTAssertEqual(try geometry(of: model), original[index], "Clipping leaves every vertex and normal unchanged")
                let parameters = parameters(for: index, view: .tacticalTable)
                try assertGeometry(model, mark: sampled, radius: parameters.radius, baseY: parameters.baseY)
            }
            try assertHighlightState(root, mark: mark)
        }
        let work = AnnotationArcMesh.work
        XCTAssertEqual(work.meshBuilds, 0)
        XCTAssertEqual(replacements, 0)
        XCTAssertEqual(work.controlPointEvaluations, times.count * 3)
        XCTAssertEqual(work.reusedMeshUpdates, times.count * 3)
        XCTAssertEqual(work.reusedMeshTransformWrites, 0)
        let report = Report(samples: times.count, meshBuilds: work.meshBuilds,
                            meshReplacements: replacements, controlPointEvaluations: work.controlPointEvaluations,
                            reusedMeshUpdates: work.reusedMeshUpdates,
                            reusedMeshTransformWrites: work.reusedMeshTransformWrites,
                            qualification: "Native mesh construction calls and resource replacements for one selected pitch-clipped arc (base plus two highlight tubes). Actual generated vertices/normals compared with the independent curve sampler. Not CPU time, GPU draw calls or headset FPS.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ClippedArcMeshWork.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealShapeTinyControlRadiusAndBaseHeightChangesRebuildTheirGeometry() throws {
        let model = placeholder()
        let initial = clippedArc(bend: 2)
        XCTAssertTrue(AnnotationArcMesh.update(model, mark: initial))
        let changes: [(CoachMark, Float, Float)] = [
            (clippedArc(bend: -2), 0.075, 0.10),
            (clippedArc(bend: -2.00001), 0.075, 0.10),
            (clippedArc(bend: -2.00001), 0.12, 0.10),
            (clippedArc(bend: -2.00001), 0.12, 0.40),
            (clippedArc(bend: 8), 0.12, 0.40),
            (clippedArc(bend: 8, lift: 1), 0.12, 0.40)
        ]
        let a = changes[0].0.resolvedCurve.controlPoint(for: changes[0].0)
        let b = changes[1].0.resolvedCurve.controlPoint(for: changes[1].0)
        XCTAssertNotEqual(a, b)
        XCTAssertLessThan(simd_distance(a, b), 0.0001, "Changed-curve reuse must not inherit the translation tolerance")
        for (mark, radius, baseY) in changes {
            let oldMesh = try XCTUnwrap(model.model?.mesh)
            AnnotationArcMesh.resetWorkForTesting()
            XCTAssertTrue(AnnotationArcMesh.update(model, mark: mark, radius: radius, baseY: baseY))
            XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 1)
            XCTAssertFalse(model.model?.mesh === oldMesh)
            try assertGeometry(model, mark: mark, radius: radius, baseY: baseY)
        }
    }

    func testClippedParameterChangesRepairExternalTransformAndSeekBackFromTranslation() throws {
        let model = placeholder()
        let initial = clippedArc(bend: 2)
        XCTAssertTrue(AnnotationArcMesh.update(model, mark: initial))
        model.transform = Transform(scale: [2, 3, 4], rotation: simd_quatf(angle: 0.6, axis: [0, 1, 0]),
                                    translation: [4, 5, 6])
        AnnotationArcMesh.resetWorkForTesting()
        let equivalent = clippedArc(bend: 10)
        XCTAssertTrue(AnnotationArcMesh.update(model, mark: equivalent))
        XCTAssertEqual(model.transform, .identity)
        try assertGeometry(model, mark: equivalent)
        let translated = clippedArc(bend: 10, shiftZ: 2)
        XCTAssertTrue(AnnotationArcMesh.update(model, mark: translated))
        XCTAssertEqual(model.position, SIMD3<Float>(0, 0, 2))
        try assertGeometry(model, mark: translated)
        XCTAssertTrue(AnnotationArcMesh.update(model, mark: initial))
        XCTAssertEqual(model.transform, .identity)
        try assertGeometry(model, mark: initial)
        XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 0)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshUpdates, 3)
        XCTAssertEqual(AnnotationArcMesh.work.reusedMeshTransformWrites, 3,
                       "External transform, translated placement and rewind each need restoration")
    }

    func testSelectedHighlightViewChangesStillRebuildThicknessAndLift() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedClippedArc()
        let root = annotationRoot()
        update(root, scenario: scenario, mark: mark, time: 4)
        let models = try arcModels(mark, in: root)
        let baseMesh = try XCTUnwrap(models[0].model?.mesh)
        for view in [ReplayViewMode.touchline, .firstPerson, .tacticalTable] {
            AnnotationArcMesh.resetWorkForTesting()
            update(root, scenario: scenario, mark: mark, time: 4, view: view)
            XCTAssertEqual(AnnotationArcMesh.work.meshBuilds, 2)
            XCTAssertTrue(models[0].model?.mesh === baseMesh)
            for (index, model) in models.enumerated() {
                let parameters = parameters(for: index, view: view)
                try assertGeometry(model, mark: mark.sampled(at: 4), radius: parameters.radius, baseY: parameters.baseY)
            }
            try assertHighlightState(root, mark: mark)
        }
    }

    private func assertGeometry(_ model: ModelEntity, mark: CoachMark, radius: Float = 0.075,
                                baseY: Float = 0.10, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try geometry(of: model)
        let expected = referenceGeometry(mark, radius: radius, baseY: baseY)
        XCTAssertEqual(actual.positions.count, expected.positions.count, file: file, line: line)
        XCTAssertEqual(actual.normals.count, expected.normals.count, file: file, line: line)
        for (position, expectedPosition) in zip(actual.positions, expected.positions) {
            let converted = model.transform.matrix * SIMD4<Float>(position.x, position.y, position.z, 1)
            assertVector([converted.x, converted.y, converted.z], expectedPosition, file: file, line: line)
        }
        for (normal, expectedNormal) in zip(actual.normals, expected.normals) {
            assertVector(model.orientation.act(normal), expectedNormal, file: file, line: line)
        }
    }

    private func referenceGeometry(_ mark: CoachMark, radius: Float, baseY: Float) -> Geometry {
        // Use the old per-sample domain method, not the mesh cache's key math.
        let curve = mark.resolvedCurve
        let start = curve.point(at: 0, for: mark)
        let end = curve.point(at: 1, for: mark)
        let plane = simd_cross(curve.controlPoint(for: mark) - start, end - start)
        let planeNormal: SIMD3<Float>? = simd_length_squared(plane) > 0.000001 ? simd_normalize(plane) : nil
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        for ring in 0...CoachMarkCurve.segmentCount {
            let t = Float(ring) / Float(CoachMarkCurve.segmentCount)
            let centre = curve.point(at: t, for: mark, baseY: baseY)
            let delta = curve.point(at: min(1, t + 0.001), for: mark)
                - curve.point(at: max(0, t - 0.001), for: mark)
            let tangent = simd_length_squared(delta) > 0.0000001 ? simd_normalize(delta) : SIMD3<Float>(0, 0, 1)
            let reference = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let side = planeNormal ?? simd_normalize(simd_cross(reference, tangent))
            let up = simd_normalize(simd_cross(tangent, side))
            for corner in 0..<6 {
                let angle = Float(corner) * 2 * Float.pi / 6
                let normal = side * cos(angle) + up * sin(angle)
                positions.append(centre + normal * radius)
                normals.append(normal)
            }
        }
        return Geometry(positions: positions, normals: normals)
    }

    private func geometry(of model: ModelEntity) throws -> Geometry {
        let mesh = try XCTUnwrap(model.model?.mesh)
        let content = try XCTUnwrap(mesh.contents.models.first)
        let part = try XCTUnwrap(content.parts.first)
        return Geometry(positions: Array(part.positions.elements),
                        normals: Array(try XCTUnwrap(part.normals).elements))
    }

    private func arcModels(_ mark: CoachMark, in root: Entity) throws -> [ModelEntity] {
        let base = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
            .findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
        let rail = try XCTUnwrap(root.findEntity(named: "annotation-selection-rail") as? ModelEntity)
        let core = try XCTUnwrap(root.findEntity(named: "annotation-selection-core") as? ModelEntity)
        return [base, rail, core]
    }

    private func assertHighlightState(_ root: Entity, mark: CoachMark) throws {
        for name in [AnnotationSceneAffordance.selectionRootName, "annotation-selection-path",
                     "annotation-target-start-\(mark.id.uuidString)", "annotation-target-end-\(mark.id.uuidString)"] {
            XCTAssertTrue(try XCTUnwrap(root.findEntity(named: name)).isEnabled)
        }
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "annotation-selection-zone")).isEnabled)
    }

    private func parameters(for index: Int, view: ReplayViewMode) -> (radius: Float, baseY: Float) {
        guard index > 0 else { return (0.075, 0.10) }
        let scale = AnnotationSceneAffordance.visualScale(for: view)
        let lift = AnnotationSceneAffordance.selectionLift(for: view)
        return index == 1 ? (0.12 * scale, lift) : (0.038 * scale, lift + 0.015)
    }

    private func clippedArc(bend: Float, lift: Float = 0, shiftZ: Float = 0) -> CoachMark {
        CoachMark(kind: .arc, start: .init(x: -34, z: -20 + shiftZ), end: .init(x: -34, z: 20 + shiftZ),
                  curve: .init(bend: bend, lift: lift), label: "Clipped arc", revealTime: 0)
    }

    private func animatedClippedArc() -> CoachMark {
        let first = clippedArc(bend: 2)
        var last = CoachMark(id: first.id, kind: .arc, start: first.start, end: first.end,
                             curve: .init(bend: 10, lift: 0), label: first.label, revealTime: 0)
        last.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        return last
    }

    private func annotationRoot() -> Entity {
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        root.addChild(marks)
        root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
        return root
    }

    private func placeholder() -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: 0.1), materials: [UnlitMaterial(color: .white)])
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval,
                        view: ReplayViewMode = .tacticalTable) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                                 selectedAnnotationID: mark.id, selectedAnnotationIsEditable: true,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }
}
