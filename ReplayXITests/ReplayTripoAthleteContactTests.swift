import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayTripoAthleteContactTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetProviders()
    }

    override func tearDown() {
        resetProviders()
        super.tearDown()
    }

    func testNearAndLowBootMarkersMeetFlatAndLoftSpheresAndRewindExactly() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let player = PlayerTrack(id: "tripo-contact-test", displayName: "Contact", role: "CM",
            shirtNumber: 8, team: .home, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                        .init(time: 2, position: .init(x: 0, z: 0), facingDegrees: 0)])

        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplayTripoAthleteProvider.make(for: player, detail: detail)
            let markers = try XCTUnwrap(skin.bootMarkers)
            XCTAssertEqual(markers.markers.count, 2)
            for side in [ReplayAthleteLeg.left, .right] {
                for direction in [SIMD3<Float>(0, 0, 1), simd_normalize(SIMD3<Float>(0, 0.65, 0.76))] {
                    let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: .pass,
                        contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: side,
                        contactBallWorldPosition: [side == .right ? 0.137 : -0.137, 0.11, 0.42],
                        outgoingDirectionWorld: direction,
                        supportFootWorldPosition: [side == .right ? -0.137 : 0.137, 0, 0.035])
                    XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                        lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue))
                    let first = skin.pose.rotations.map(\.vector)
                    let marker = try XCTUnwrap(markers.markers.first {
                        (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0)
                            == (side == .left)
                    })
                    let actual4 = skin.pose.modelSpaceTransforms[marker.ankleIndex]
                        * SIMD4(marker.ankleLocalPosition, 1)
                    let actual = SIMD3<Float>(actual4.x,
                        actual4.y - skin.motion.geometry.restMinY, actual4.z)
                    let expected = cue.contactBallWorldPosition
                        - direction * ReplayAthleteInteractionPose.ballRadius
                    XCTAssertLessThanOrEqual(simd_distance(actual, expected), 0.03,
                        "\(detail) \(side) boot marker misses flat/loft sphere")
                    XCTAssertGreaterThanOrEqual(
                        skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                        skin.contactSurface.paddingMetres - 0.000_01)

                    for time in [1.15, 0.85, 1.0] {
                        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                            lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue))
                    }
                    XCTAssertEqual(first, skin.pose.rotations.map(\.vector),
                        "\(detail) \(side) contact pose must replay identically after rewind")
                }
            }
        }
    }

    func testReferenceHeadersStayWithinThreeCentimetresOfActualHeadTriangles() async throws {
        try ReplayTripoAthleteProvider.prewarm()
        var diagnostics: [[String: Any]] = []
        for scenarioIndex in [1, 3] {
            let scenario = FootballReferenceScenarios.all[scenarioIndex]
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            let headers = recording.touches.filter { $0.kind == .header }
            XCTAssertEqual(headers.count, 1, scenario.id)
            let touch = try XCTUnwrap(headers.first)
            let player = try XCTUnwrap(scenario.player(id: touch.playerID))
            let presented = player.presentationPose(at: touch.time)
            let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: .header,
                contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                outgoingDirectionWorld: touch.outgoingVelocity, headerSupportLeg: touch.headerSupportLeg)

            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplayTripoAthleteProvider.make(for: player, detail: detail)
                let actor = Entity()
                actor.position = [presented.position.x, 0, presented.position.z]
                actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180,
                                               axis: [0, 1, 0])
                actor.addChild(skin.root)
                var stageRootY: [String: Float] = [:]
                skin.poseStageObserverForTesting = { stage, pose in
                    if stage == .headerAim || stage == .cervical || stage == .finalFloor {
                        stageRootY[stage.rawValue] = pose.translations[0].y
                    }
                }
                XCTAssertTrue(skin.update(at: touch.time, track: player,
                    locomotion: player.locomotion(at: touch.time), lookTarget: touch.position,
                    ballAction: nil, interaction: cue, presentationPose: presented))
                skin.poseStageObserverForTesting = nil
                let audit = try headTriangles(skin.model, motion: skin.motion)
                let triangles = audit.triangles
                XCTAssertGreaterThan(triangles.count, 20, "\(scenario.id) \(detail) needs actual head triangles")
                let nearest = try XCTUnwrap(triangles.map {
                    nearestPoint(touch.position, $0.0, $0.1, $0.2)
                }.min { simd_distance_squared($0, touch.position) < simd_distance_squared($1, touch.position) })
                let gap = simd_distance(nearest, touch.position) - ReplayNativeBallPhysics.radius
                func pivot(_ index: Int) -> [String: [Float]] {
                    let matrix = skin.pose.modelSpaceTransforms[index]
                    let local = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
                    let world = skin.model.convert(position: local, to: nil)
                    return ["local": vector(local), "world": vector(world)]
                }
                let rootPivot = pivot(try XCTUnwrap(skin.motion.semanticJointIndices["hips"]))
                let chestPivot = pivot(skin.motion.numberAnchors.jointIndex)
                let headPivot = pivot(try XCTUnwrap(skin.motion.semanticJointIndices["head"]))
                stageRootY["final"] = skin.pose.translations[0].y
                diagnostics.append([
                    "scenario": scenario.id, "detail": String(describing: detail),
                    "playerID": player.id, "time": touch.time,
                    "signedGapMetres": gap, "ballCentreWorld": vector(touch.position),
                    "nearestHeadPointWorld": vector(nearest),
                    "headerSupportLeg": touch.headerSupportLeg?.rawValue ?? "none",
                    "posedPivots": ["root": rootPivot, "chest": chestPivot, "head": headPivot],
                    "rootTranslationY": skin.pose.translations[0].y,
                    "stageRootTranslationY": stageRootY,
                    "headerProbeCount": skin.contactSurface.headerProbeCount,
                    "headSubtreeQualifyingVertices": audit.qualifyingVertexCount,
                    "bodyVertexCount": audit.vertexCount,
                    "selectedHeadTriangleCount": triangles.count
                ])
                print("[TripoHeader] \(scenario.id) \(detail) signedGap=\(gap) ball=\(vector(touch.position)) nearest=\(vector(nearest)) support=\(touch.headerSupportLeg?.rawValue ?? "none") root=\(rootPivot["world"] ?? []) chest=\(chestPivot["world"] ?? []) head=\(headPivot["world"] ?? []) probes=\(skin.contactSurface.headerProbeCount) selectedTriangles=\(triangles.count)")
                XCTAssertLessThanOrEqual(abs(gap), 0.03,
                    "\(scenario.id) \(detail) actual single-body head surface must meet the ball sphere")
            }
        }
        let attachment = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Tripo-Reference-Header-Contact-Diagnostics.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func headTriangles(_ model: ModelEntity, motion: ReplaySkinnedAthleteMotion)
        throws -> (triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)],
                   qualifyingVertexCount: Int, vertexCount: Int) {
        let contents = try XCTUnwrap(model.model).mesh.contents
        let parts = contents.models.flatMap { Array($0.parts) }
        XCTAssertEqual(parts.count, 1, "The Tripo skin must remain a single-body mesh")
        let part = try XCTUnwrap(parts.first)
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let semanticHead = try XCTUnwrap(motion.semanticJointIndices["head"])
        var headSubtree = Set<Int>()
        for index in motion.joints.indices {
            var candidate = index
            while candidate >= 0 {
                if candidate == semanticHead {
                    headSubtree.insert(index)
                    break
                }
                candidate = motion.joints[candidate].parentIndex
            }
        }

        let native = model.jointTransforms
        XCTAssertEqual(native.count, motion.joints.count)
        var matrices = Array(repeating: matrix_identity_float4x4, count: native.count)
        for index in native.indices {
            let parent = motion.joints[index].parentIndex
            matrices[index] = (parent < 0 ? matrix_identity_float4x4 : matrices[parent]) * native[index].matrix
        }
        let influences = try XCTUnwrap(part.jointInfluences).influences.elements
        let count = part.positions.count
        let influenceStride = influences.count / max(count, 1)
        XCTAssertTrue((1...8).contains(influenceStride))
        XCTAssertEqual(influences.count, count * influenceStride)
        let positions = part.positions.elements
        var vertices = Array(repeating: SIMD3<Float>.zero, count: count)
        var headWeights = Array(repeating: Float.zero, count: count)
        for index in 0..<count {
            var point = SIMD4<Float>.zero
            for influence in influences[(index * influenceStride)..<((index + 1) * influenceStride)] {
                if headSubtree.contains(influence.jointIndex) { headWeights[index] += influence.weight }
                point += (matrices[influence.jointIndex]
                    * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                    * SIMD4(positions[index], 1)) * influence.weight
            }
            vertices[index] = SIMD3(point.x, point.y, point.z)
        }

        let indices = try XCTUnwrap(part.triangleIndices).elements
        XCTAssertEqual(indices.count % 3, 0)
        var result: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            guard headWeights[a] >= 0.8, headWeights[b] >= 0.8, headWeights[c] >= 0.8 else { continue }
            result.append((model.convert(position: vertices[a], to: nil),
                           model.convert(position: vertices[b], to: nil),
                           model.convert(position: vertices[c], to: nil)))
        }
        return (result, headWeights.filter { $0 >= 0.8 }.count, count)
    }

    private func nearestPoint(_ point: SIMD3<Float>, _ a: SIMD3<Float>,
                              _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a
        let normal = simd_cross(ab, ac)
        let squaredNormal = simd_length_squared(normal)
        if squaredNormal > 0.000_000_000_1 {
            let projected = point - normal * (simd_dot(point - a, normal) / squaredNormal)
            let relative = projected - a
            let aa = simd_dot(ab, ab), bb = simd_dot(ab, ac), cc = simd_dot(ac, ac)
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
        return [edge(a, b), edge(b, c), edge(c, a)].min {
            simd_distance_squared(point, $0) < simd_distance_squared(point, $1)
        }!
    }

    private func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }

    private func resetProviders() {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
    }
}
