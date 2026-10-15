import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Compare the label anchor with the whole imported head surface, not the
/// reduced contact probes or the motion buffer used by the implementation.
@MainActor
final class ReplayPlayerCrownSurface176Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayTripoAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private struct Influence {
        let joint: Int
        let bindPoint: SIMD4<Float>
        let weight: Float
    }

    private struct HeadSurface {
        let points: [[Influence]]
        let parents: [Int]

        init(_ skin: ReplaySkinnedAthleteInstance) throws {
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            let part = try XCTUnwrap(contents.models.first?.parts.first)
            let weights = try XCTUnwrap(part.jointInfluences).influences.elements
            let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            XCTAssertEqual(weights.count, part.positions.count * 4)
            let neckY = skin.motion.restPose.modelSpaceTransforms[neck].columns.3.y
            parents = skin.motion.joints.map(\.parentIndex)
            points = part.positions.elements.enumerated().compactMap { index, point in
                let blend = weights[(index * 4)..<(index * 4 + 4)]
                let cervicalShare = blend.filter { $0.jointIndex == neck || $0.jointIndex == head }
                    .reduce(Float.zero) { $0 + $1.weight }
                guard point.y >= neckY, cervicalShare >= 0.5 else { return nil }
                return blend.map { Influence(joint: $0.jointIndex,
                    bindPoint: skeleton.joints[$0.jointIndex].inverseBindPoseMatrix * SIMD4(point, 1),
                    weight: $0.weight) }
            }
            XCTAssertGreaterThan(points.count, 30, "Oracle must cover the actual head, not a single pivot")
        }

        func maximumY(_ skin: ReplaySkinnedAthleteInstance, relativeTo player: Entity) throws -> Float {
            // Build FK from transforms submitted to RealityKit independently
            // of skin.pose and the runtime's reduced contact surface.
            let local = skin.model.jointTransforms
            XCTAssertEqual(local.count, parents.count)
            var world = [simd_float4x4]()
            world.reserveCapacity(local.count)
            for index in local.indices {
                let parent = parents[index]
                world.append((parent >= 0 ? world[parent] : matrix_identity_float4x4) * local[index].matrix)
            }
            let transform = skin.model.transformMatrix(relativeTo: player)
            let heights = points.map { influences -> Float in
                let point = influences.reduce(SIMD4<Float>.zero) {
                    $0 + world[$1.joint] * $1.bindPoint * $1.weight
                }
                return (transform * point).y
            }
            return try XCTUnwrap(heights.max())
        }
    }

    private func player(keeper: Bool = false) -> PlayerTrack {
        .init(id: keeper ? "crown-keeper" : "crown-runner", displayName: "Crown test",
            role: keeper ? "GK" : "CM", shirtNumber: 3, team: .home, isGoalkeeper: keeper,
            keyframes: [
                .init(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                .init(time: 4, position: .init(x: 0, z: keeper ? 0 : 12), facingDegrees: 0)
            ])
    }

    private func compare(_ skin: ReplaySkinnedAthleteInstance, surface: HeadSurface,
                         player: Entity, context: String) throws {
        let actual = try XCTUnwrap(skin.headMaximumYInPlayerLocalSpace(), context)
        let expected = try surface.maximumY(skin, relativeTo: player)
        XCTAssertTrue(actual.isFinite, context)
        XCTAssertEqual(actual, expected, accuracy: 0.02,
            "\(context): probe crown=\(actual), full rendered head crown=\(expected)")
    }

    func testCrownMatchesRenderedHeadAcrossBothBodiesLODsMotionAndReverseSeek() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed)
        let track = player()
        for diverse in [false, true] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try diverse ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                    : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                let container = Entity()
                container.addChild(skin.root)
                let surface = try HeadSurface(skin)
                for speed: Float in [0, 1.1, 4.8] {
                    var firstCrown: Float?
                    for time in [0.35, 1.7, 3.2, 0.35] {
                        let locomotion = PlayerLocomotionSample(motion: track.locomotion(at: time).motion,
                            speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
                            turnRateDegreesPerSecond: speed > 0 ? 100 : 0,
                            state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                turnRateDegreesPerSecond: speed > 0 ? 100 : 0))
                        let look: SIMD3<Float> = time > 1 ? [-8, 0.1, -5] : [8, 2.8, 3]
                        XCTAssertTrue(skin.update(at: time, track: track, locomotion: locomotion,
                            lookTarget: look, ballAction: nil,
                            stationaryPose: speed == 0 ? track.presentationPose(at: time) : nil,
                            presentationPose: track.presentationPose(at: time)))
                        try compare(skin, surface: surface, player: container,
                            context: "diverse=\(diverse) \(detail) speed=\(speed) time=\(time)")
                        let crown = try XCTUnwrap(skin.headMaximumYInPlayerLocalSpace())
                        if time == 0.35 {
                            if let firstCrown { XCTAssertEqual(crown, firstCrown, accuracy: 0.000_01) }
                            else { firstCrown = crown }
                        }
                    }
                }
            }
        }
    }

    func testCrouchedCrownUsesAppearanceScaleButExcludesPlayerContainerTransform() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = player(keeper: true)
        for diverse in [false, true] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try diverse ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                    : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                let container = Entity()
                container.addChild(skin.root)
                let surface = try HeadSurface(skin)
                let ball: SIMD3<Float> = [1, 0.11, 3]
                let ready = try XCTUnwrap(ReplayGoalkeeperReadiness.sample(track: track, at: 1,
                    presentationPose: track.presentationPose(at: 1), ballPosition: ball))
                XCTAssertGreaterThan(ready.crouchMetres, 0)
                XCTAssertTrue(skin.update(at: 1, track: track, locomotion: track.locomotion(at: 1),
                    lookTarget: ball, ballAction: nil, presentationPose: track.presentationPose(at: 1),
                    goalkeeperReadiness: ready))
                let before = try XCTUnwrap(skin.headMaximumYInPlayerLocalSpace())
                skin.root.scale.y *= 0.82
                skin.root.position.y += 0.13
                let scaled = try XCTUnwrap(skin.headMaximumYInPlayerLocalSpace())
                XCTAssertEqual(scaled, before * 0.82 + 0.13, accuracy: 0.000_01)
                container.scale = [0.31, 0.31, 0.31]
                container.position = [4, 0.8, -2]
                container.orientation = simd_quatf(angle: 1.2, axis: [0, 1, 0])
                XCTAssertEqual(try XCTUnwrap(skin.headMaximumYInPlayerLocalSpace()), scaled,
                    accuracy: 0.000_01, "Scene must apply player transform once, not twice")
                try compare(skin, surface: surface, player: container,
                    context: "crouch diverse=\(diverse) \(detail)")
            }
        }
    }
}
