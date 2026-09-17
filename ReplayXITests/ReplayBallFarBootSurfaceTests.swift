import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayBallFarBootSurfaceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplayArticulatedFarProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        super.tearDown()
    }

    func testActualFarWingerBootSurfacesClearTheDisplayedBallAroundThePass() throws {
        try check(playerID: "navy-rw", contactTime: 13.6)
    }

    func testActualFarRightBackBootSurfacesClearTheDisplayedBallAroundTheCutback() throws {
        try check(playerID: "navy-rb", contactTime: 17.5)
    }

    private func check(playerID: String, contactTime: Double) throws {
        try ReplayArticulatedFarProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var report: [[String: Any]] = []
        for time in [contactTime - 0.08, contactTime, contactTime + 0.08, contactTime] {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                viewMode: .tacticalTable, perspectiveID: "navy-gk", marks: [],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
            let actor = try XCTUnwrap(root.findEntity(named: "player-\(playerID)"))
            let rig = try XCTUnwrap(actor.findEntity(named: "table-marker"))
            XCTAssertTrue(rig.isEnabledInHierarchy)
            XCTAssertEqual(actor.scale, .one)
            let ball = try XCTUnwrap(root.findEntity(named: "ball"))
            XCTAssertEqual(ball.scale, .one)
            let centre = ball.position(relativeTo: root)
            var minimum: Float = .greatestFiniteMagnitude
            var triangles = 0
            for name in ["left-leg", "right-leg"] {
                let model = try XCTUnwrap(rig.findEntity(named: name) as? ModelEntity)
                let surface = try bootTriangles(in: model, relativeTo: root)
                triangles += surface.count
                for triangle in surface {
                    minimum = min(minimum, simd_distance(centre,
                        nearestPoint(centre, triangle.0, triangle.1, triangle.2)))
                }
            }
            XCTAssertGreaterThan(triangles, 30, "Must measure actual imported boot faces, not an empty subset")
            let gap = minimum - ReplayBallPlaybackMotion.ballRadius
            XCTAssertGreaterThanOrEqual(gap, -0.001,
                                       "\(playerID) at \(time): rendered ball intersects a deformed boot surface")
            if time == contactTime {
                XCTAssertLessThan(gap, 0.20, "The contact should remain near the boot, not be hidden far away")
            }
            report.append(["player": playerID, "time": time, "bootTriangles": triangles,
                           "ballCentre": [centre.x, centre.y, centre.z],
                           "minimumBootSurfaceGapMetres": gap])
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "samples": report,
            "scope": "Actual native articulated far boot triangles and ball sphere at two authored contacts ±0.08s; not whole-match mesh collision proof",
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Ball-FarBoot-Surface-\(playerID).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Test-owned LBS from the live ModelEntity's transforms, imported weights,
    /// inverse binds and triangle indices. The new asset assigns boot faces to
    /// the ankle/Tip joint with full weight; mixed knee faces are excluded.
    private func bootTriangles(in model: ModelEntity, relativeTo root: Entity) throws
        -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        let contents = try XCTUnwrap(model.model).mesh.contents
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let part = try XCTUnwrap(contents.models.first?.parts.first)
        let joints = model.jointTransforms
        XCTAssertEqual(joints.count, 3)
        let matrices = [joints[0].matrix, joints[0].matrix * joints[1].matrix,
                        joints[0].matrix * joints[1].matrix * joints[2].matrix]
        let influences = try XCTUnwrap(part.jointInfluences).influences.elements
        let weightStride = influences.count / part.positions.count
        XCTAssertGreaterThan(weightStride, 0)
        var vertices: [SIMD3<Float>] = []
        var bootVertex: [Bool] = []
        for (index, position) in part.positions.elements.enumerated() {
            var deformed = SIMD4<Float>.zero
            var tipWeight: Float = 0
            for influence in influences[(index * weightStride)..<((index + 1) * weightStride)] {
                deformed += (matrices[influence.jointIndex]
                    * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                    * SIMD4(position, 1)) * influence.weight
                if influence.jointIndex == 2 { tipWeight += influence.weight }
            }
            vertices.append(model.convert(position: [deformed.x, deformed.y, deformed.z], to: root))
            bootVertex.append(tipWeight > 0.999)
        }
        let indices = try XCTUnwrap(part.triangleIndices).elements
        var result: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset])
            let b = Int(indices[offset + 1])
            let c = Int(indices[offset + 2])
            if bootVertex[a], bootVertex[b], bootVertex[c] {
                result.append((vertices[a], vertices[b], vertices[c]))
            }
        }
        return result
    }

    private func nearestPoint(_ point: SIMD3<Float>, _ a: SIMD3<Float>,
                              _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a
        let ac = c - a
        let normal = simd_cross(ab, ac)
        let squaredNormal = simd_length_squared(normal)
        if squaredNormal > 0.000_000_000_1 {
            let projected = point - normal * (simd_dot(point - a, normal) / squaredNormal)
            let relative = projected - a
            let aa = simd_dot(ab, ab)
            let bb = simd_dot(ab, ac)
            let cc = simd_dot(ac, ac)
            let denominator = aa * cc - bb * bb
            if abs(denominator) > 0.000_000_000_1 {
                let u = (cc * simd_dot(relative, ab) - bb * simd_dot(relative, ac)) / denominator
                let v = (aa * simd_dot(relative, ac) - bb * simd_dot(relative, ab)) / denominator
                if u >= 0, v >= 0, u + v <= 1 { return projected }
            }
        }
        func edge(_ start: SIMD3<Float>, _ end: SIMD3<Float>) -> SIMD3<Float> {
            let delta = end - start
            let length = simd_length_squared(delta)
            let t = length > 0.000_000_000_1
                ? min(max(simd_dot(point - start, delta) / length, 0), 1) : 0
            return start + delta * t
        }
        let candidates = [edge(a, b), edge(b, c), edge(c, a)]
        return candidates.min { simd_length_squared(point - $0) < simd_length_squared(point - $1) }!
    }
}
