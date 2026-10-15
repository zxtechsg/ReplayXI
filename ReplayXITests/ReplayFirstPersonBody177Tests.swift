import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayFirstPersonBody177Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayTripoAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private struct Vertex: Hashable {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let uv: SIMD2<Float>
        let joints: SIMD4<Int32>
        let weights: SIMD4<Float>
    }

    private func vertices(_ mesh: MeshResource) throws -> [Vertex] {
        let part = try XCTUnwrap(mesh.contents.models.first?.parts.first)
        let normals = try XCTUnwrap(part.normals).elements
        let uvs = try XCTUnwrap(part.textureCoordinates).elements
        let weights = try XCTUnwrap(part.jointInfluences).influences.elements
        return part.positions.elements.enumerated().map { index, position in
            let base = index * 4
            return Vertex(position: position, normal: normals[index], uv: uvs[index],
                joints: .init(Int32(weights[base].jointIndex), Int32(weights[base + 1].jointIndex),
                              Int32(weights[base + 2].jointIndex), Int32(weights[base + 3].jointIndex)),
                weights: .init(weights[base].weight, weights[base + 1].weight,
                               weights[base + 2].weight, weights[base + 3].weight))
        }
    }

    private func player(team: FootballTeam = .home) -> PlayerTrack {
        PlayerTrack(id: "fpv-body", displayName: "FPV player", role: "CM", shirtNumber: 3,
            team: team, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .init(x: 0, z: -4), facingDegrees: 0),
                        .init(time: 4, position: .init(x: 0, z: 8), facingDegrees: 0)])
    }

    func testBothIdentitiesKeepExactLegGeometryWeightsAndUVsAtBothDetails() throws {
        try ReplayTripoAthleteProvider.prewarm()
        for diverse in [false, true] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let track = player()
                let skin = try diverse
                    ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                    : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                let complete = try XCTUnwrap(skin.model.model?.mesh)
                let original = try vertices(complete)
                XCTAssertTrue(skin.setFirstPersonBodyPresentation(true), "\(diverse) \(detail)")
                let clipped = try XCTUnwrap(skin.model.model?.mesh)
                let body = try vertices(clipped)
                let bodySet = Set(body)
                XCTAssertTrue(bodySet.isSubset(of: Set(original)),
                              "FPV cannot change retained skin geometry, UVs or rig weights")
                XCTAssertTrue(Set(original.filter { $0.position.y < 0.25 }).isSubset(of: bodySet),
                              "Every boot vertex must survive the head cut")
                XCTAssertTrue(Set(original.filter { abs($0.position.x) > 0.26 && $0.position.y < 1.35 })
                    .isSubset(of: bodySet), "Arms and hands must remain, not leave a hollow waist-only body")
                XCTAssertGreaterThan(body.count, 100)
                XCTAssertLessThan(body.count, original.count)
                XCTAssertLessThan(try XCTUnwrap(body.map(\.position.y).max()), 1.60)
                XCTAssertGreaterThan(try XCTUnwrap(body.map(\.position.y).max()), 1.47,
                                     "Keep chest and shoulders, not a waist-high opening")
                let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
                XCTAssertTrue(body.allSatisfy { vertex in
                    (0..<4).reduce(Float.zero) { total, slot in
                        total + (Int(vertex.joints[slot]) == head ? vertex.weights[slot] : 0)
                    } < 0.75
                }, "Skull-dominated vertices must never enclose the eye camera")
                let cap = try XCTUnwrap(clipped.contents.models.first?.parts.first {
                    $0.id == "first-person-neck-cap"
                })
                let capPositions = cap.positions.elements
                let capWeights = try XCTUnwrap(cap.jointInfluences).influences.elements
                let capIndices = try XCTUnwrap(cap.triangleIndices).elements
                XCTAssertGreaterThanOrEqual(capPositions.count, 4)
                XCTAssertLessThanOrEqual(capPositions.count, 129)
                XCTAssertEqual(capIndices.count, (capPositions.count - 1) * 3)
                XCTAssertEqual(capWeights.count, capPositions.count * 4)
                let sourceIndices = try XCTUnwrap(complete.contents.models.first?.parts.first?
                    .triangleIndices?.elements)
                var cutPositions = Set<SIMD3<Float>>()
                for offset in stride(from: 0, to: sourceIndices.count, by: 3) {
                    let triangle = (0..<3).map { original[Int(sourceIndices[offset + $0])] }
                    if !triangle.allSatisfy(bodySet.contains) {
                        cutPositions.formUnion(triangle.map(\.position))
                    }
                }
                let geometricRim = body.map(\.position).filter { point in
                    cutPositions.contains(point)
                        && point.y > skin.motion.geometry.restMinY + skin.motion.geometry.nominalHeight * 0.76
                        && abs(point.x) < 0.16 && abs(point.z) < 0.20
                }
                XCTAssertGreaterThanOrEqual(geometricRim.count, 3)
                for axis in [0, 2] {
                    XCTAssertEqual(try XCTUnwrap(capPositions.map { $0[axis] }.min()),
                        try XCTUnwrap(geometricRim.map { $0[axis] }.min()), accuracy: 0.000_01,
                        "The closure must span the full geometric cut, including UV-split seams")
                    XCTAssertEqual(try XCTUnwrap(capPositions.map { $0[axis] }.max()),
                        try XCTUnwrap(geometricRim.map { $0[axis] }.max()), accuracy: 0.000_01)
                }
                for (index, position) in capPositions.dropLast().enumerated() {
                    XCTAssertTrue(body.contains { vertex in
                        vertex.position == position && (0..<4).allSatisfy { slot in
                            Int(vertex.joints[slot]) == capWeights[index * 4 + slot].jointIndex
                                && vertex.weights[slot] == capWeights[index * 4 + slot].weight
                        }
                    }, "Neck closure edges must follow the exact existing skin weights")
                }
                for offset in stride(from: 0, to: capIndices.count, by: 3) {
                    let a = capPositions[Int(capIndices[offset])]
                    let b = capPositions[Int(capIndices[offset + 1])]
                    let c = capPositions[Int(capIndices[offset + 2])]
                    XCTAssertGreaterThan(simd_cross(b - a, c - a).y, 0,
                                         "The neck closure must face the overhead eye camera")
                }
                XCTAssertEqual(capWeights.suffix(4).reduce(Float.zero) { $0 + $1.weight }, 1, accuracy: 0.0001)
                XCTAssertEqual(clipped.contents.skeletons.first?.joints,
                               complete.contents.skeletons.first?.joints)
                XCTAssertEqual(skin.model.jointNames, skin.motion.jointNames)
                XCTAssertFalse(skin.front.isEnabled)
                XCTAssertFalse(skin.back.isEnabled)
                XCTAssertFalse(skin.neckBridge?.isEnabled ?? false)
                XCTAssertTrue(skin.isFirstPersonBodyPresentation)
                XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
                XCTAssertTrue(skin.model.model?.mesh === complete)
                XCTAssertTrue(skin.front.isEnabled)
                XCTAssertTrue(skin.back.isEnabled)
                XCTAssertTrue(skin.neckBridge?.isEnabled ?? true)
            }
        }
    }

    func testFirstPersonMeshIsSharedAndModeChangesNeverReloadAssets() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let loadAttempts = ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting
        for diverse in [false, true] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let a = try diverse
                    ? ReplayTripoAthleteProvider.makeDiverse(for: player(), detail: detail)
                    : ReplayTripoAthleteProvider.make(for: player(), detail: detail)
                let b = try diverse
                    ? ReplayTripoAthleteProvider.makeDiverse(for: player(team: .away), detail: detail)
                    : ReplayTripoAthleteProvider.make(for: player(team: .away), detail: detail)
                XCTAssertTrue(a.setFirstPersonBodyPresentation(true))
                XCTAssertTrue(b.setFirstPersonBodyPresentation(true))
                let shared = try XCTUnwrap(a.model.model?.mesh)
                XCTAssertTrue(shared === b.model.model?.mesh)
                for _ in 0..<20 {
                    XCTAssertTrue(a.setFirstPersonBodyPresentation(true))
                    XCTAssertTrue(a.model.model?.mesh === shared)
                    XCTAssertTrue(a.setFirstPersonBodyPresentation(false))
                    XCTAssertTrue(a.setFirstPersonBodyPresentation(true))
                    XCTAssertTrue(a.model.model?.mesh === shared)
                }
            }
        }
        XCTAssertEqual(ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting, loadAttempts)
    }

    func testSamePoseContactsAndReverseSeekAsTheFullBody() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = player()
        let pass = ReplayAthleteInteractionCue(playerID: track.id, kind: .pass,
            contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
            contactBallWorldPosition: [0.137, 0.11, 0.42], outgoingDirectionWorld: [0, 0, 1],
            supportFootWorldPosition: [-0.137, 0, 0.035])
        for diverse in [false, true] {
            let skin = try diverse
                ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: .near)
                : ReplayTripoAthleteProvider.make(for: track, detail: .near)
            func seek(_ time: Double, interaction: ReplayAthleteInteractionCue? = nil) {
                XCTAssertTrue(skin.update(at: time, track: track,
                    locomotion: track.locomotion(at: time), lookTarget: [4, 1.5, 9],
                    ballAction: nil, interaction: interaction))
            }
            for cue: ReplayAthleteInteractionCue? in [nil, pass] {
                XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
                seek(1, interaction: cue)
                let fullTransforms = skin.model.jointTransforms
                let fullGround = skin.contactSurface.minimumY(in: skin.pose)
                let originalPlacement = skin.root.transform
                XCTAssertTrue(skin.setFirstPersonBodyPresentation(true))
                XCTAssertEqual(skin.model.jointTransforms, fullTransforms)
                seek(1, interaction: cue)
                XCTAssertEqual(skin.model.jointTransforms, fullTransforms)
                XCTAssertEqual(skin.contactSurface.minimumY(in: skin.pose), fullGround)
                XCTAssertEqual(skin.root.transform, originalPlacement)
                seek(3); seek(0.2); seek(1, interaction: cue)
                XCTAssertEqual(skin.model.jointTransforms, fullTransforms)
                XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
                XCTAssertEqual(skin.model.jointTransforms, fullTransforms)
                XCTAssertEqual(skin.front.jointTransforms, fullTransforms)
                XCTAssertEqual(skin.back.jointTransforms, fullTransforms)
            }
        }
    }

    func testUnsupportedMeshReturnsFailureAndPreservesFullBody() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let source = try ReplayTripoAthleteProvider.make(for: player())
        let root = Entity(), skinRoot = Entity()
        let model = source.model.clone(recursive: true)
        root.addChild(skinRoot); skinRoot.addChild(model)
        let skin = ReplaySkinnedAthleteInstance(root: root, skinRoot: skinRoot,
            model: model, front: ModelEntity(), back: ModelEntity(), playerID: source.playerID,
            motion: source.motion, contactSurface: source.contactSurface)
        let complete = model.model?.mesh
        XCTAssertFalse(skin.setFirstPersonBodyPresentation(true))
        XCTAssertFalse(skin.isFirstPersonBodyPresentation)
        XCTAssertTrue(model.model?.mesh === complete)
        XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
    }
}
