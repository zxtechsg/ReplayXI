import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteRuntimeTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare() throws -> (PlayerTrack, ReplaySkinnedAthleteInstance) {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        return (player, try ReplaySkinnedAthleteProvider.make(for: player))
    }

    private func jogging(_ player: PlayerTrack, at time: Double) -> PlayerLocomotionSample {
        let sample = player.locomotion(at: time)
        return PlayerLocomotionSample(motion: sample.motion, speedMetresPerSecond: 3.6,
                                     accelerationMetresPerSecondSquared: 0,
                                     turnRateDegreesPerSecond: 0, state: .jog)
    }

    func testBundledRigHasVerifiedSkinAndIndependentClones() throws {
        let (player, first) = try prepare()
        let second = try ReplaySkinnedAthleteProvider.make(for: player)
        XCTAssertEqual(first.model.jointNames.count, 80)
        XCTAssertEqual(first.model.jointTransforms.count, 80)
        XCTAssertEqual(first.model.model?.materials.count, 2)
        XCTAssertTrue(first.model.model?.mesh === second.model.model?.mesh)
        XCTAssertFalse(first.model === second.model)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.materialDrawsPerInstance, 4)
        XCTAssertTrue(first.update(at: 12, track: player, locomotion: jogging(player, at: 12),
                                  lookTarget: nil, ballAction: nil, hasImpact: false))
        XCTAssertNotEqual(first.model.jointTransforms, second.model.jointTransforms)
        XCTAssertEqual(first.model.jointNames, first.motion.jointNames)
    }

    func testArbitrarySeekAndRewindHaveIdenticalSkinAndNumbers() throws {
        let (player, skin) = try prepare()
        func seek(_ time: Double) {
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                                      lookTarget: [9, 0.2, 20], ballAction: nil, hasImpact: false))
        }
        seek(12)
        let first = skin.model.jointTransforms
        let front = skin.front.transform
        let back = skin.back.transform
        seek(17)
        XCTAssertNotEqual(skin.model.jointTransforms, first)
        seek(3)
        seek(12)
        XCTAssertEqual(skin.model.jointTransforms, first)
        XCTAssertEqual(skin.front.transform, front)
        XCTAssertEqual(skin.back.transform, back)
        let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
        let expected = chest * SIMD4<Float>(skin.motion.numberAnchors.front, 1)
        XCTAssertLessThan(simd_distance(skin.front.position, SIMD3(expected.x, expected.y, expected.z)), 0.00001)
    }

    func testTurningHeadDoesNotDragShouldersWithNeck() throws {
        let (player, skin) = try prepare()
        let time = 12.0
        let pose = player.presentationPose(at: time)
        let bearing = pose.facingDegrees * .pi / 180
        func target(_ side: Float) -> SIMD3<Float> {
            [pose.position.x + sin(bearing) * 10 + cos(bearing) * side * 10,
             1.5,
             pose.position.z + cos(bearing) * 10 - sin(bearing) * side * 10]
        }
        _ = skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                        lookTarget: target(-1),
                        ballAction: nil, hasImpact: false)
        let first = skin.pose
        _ = skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                        lookTarget: target(1),
                        ballAction: nil, hasImpact: false)
        let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
        XCTAssertNotEqual(skin.pose.modelSpaceTransforms[head], first.modelSpaceTransforms[head])
        for name in ["leftShoulder", "rightShoulder", "leftWrist", "rightWrist"] {
            let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
            for column in 0..<4 {
                XCTAssertLessThan(simd_distance(skin.pose.modelSpaceTransforms[index][column],
                                                first.modelSpaceTransforms[index][column]), 0.0001, name)
            }
        }
    }

    func testFootballTouchesKeepSkinWhileImpactsUseProceduralFallback() throws {
        let (player, skin) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let time = 13.6
        let motion = jogging(player, at: time)
        let action = try XCTUnwrap(ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: motion, lookTarget: nil,
                                  ballAction: nil, hasImpact: false))
        let running = skin.model.jointTransforms
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: motion, lookTarget: nil,
                                  ballAction: action, hasImpact: false))
        XCTAssertTrue(skin.root.isEnabled)
        XCTAssertNotEqual(skin.model.jointTransforms, running)
        XCTAssertFalse(skin.update(at: time, track: player, locomotion: motion, lookTarget: nil,
                                   ballAction: action, hasImpact: true))
        XCTAssertFalse(skin.root.isEnabled)
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: motion, lookTarget: nil,
                                  ballAction: action, hasImpact: false))
    }

    private func locomotion(_ player: PlayerTrack, at time: Double, speed: Float, turn: Float = 0,
                            state: PlayerLocomotionState? = nil) -> PlayerLocomotionSample {
        PlayerLocomotionSample(motion: player.locomotion(at: time).motion, speedMetresPerSecond: speed,
                               accelerationMetresPerSecondSquared: 0, turnRateDegreesPerSecond: turn,
                               state: state ?? PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: turn))
    }

    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    func testWalkingAndCutsKeepSkinWithGroundedBootsAndConstantLegLengths() throws {
        let (player, skin) = try prepare()
        for (speed, turn) in [(Float(1.1), Float(0)), (3.0, 180), (3.0, -180)] {
            for time in stride(from: 0.0, through: 3.0, by: 0.09) {
                let sample = locomotion(player, at: time, speed: speed, turn: turn)
                XCTAssertEqual(ReplaySkinnedAthleteFootballPose.influence(locomotion: sample, ballAction: nil), 1)
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                          lookTarget: nil, ballAction: nil, hasImpact: false))
                let soles = skin.motion.footContacts.values.map {
                    (skin.pose.modelSpaceTransforms[$0.footJointIndex] * SIMD4($0.solePoint, 1)).y
                        - skin.motion.geometry.restMinY
                }
                XCTAssertEqual(try XCTUnwrap(soles.min()), 0, accuracy: 0.0001)
                XCTAssertLessThan(try XCTUnwrap(soles.max()), 0.8)
                XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
                for side in ["left", "right"] {
                    let hip = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Hip"])
                    let knee = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Knee"])
                    let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Ankle"])
                    for (first, second) in [(hip, knee), (knee, ankle)] {
                        let rest = simd_distance(position(skin.motion.restPose.modelSpaceTransforms[first]),
                                                 position(skin.motion.restPose.modelSpaceTransforms[second]))
                        let posed = simd_distance(position(skin.pose.modelSpaceTransforms[first]),
                                                  position(skin.pose.modelSpaceTransforms[second]))
                        XCTAssertEqual(posed, rest, accuracy: 0.0001, side)
                    }
                }
            }
        }
    }

    func testFootballSkinIsContinuousAcrossSemanticMotionBoundaries() throws {
        let (player, skin) = try prepare()
        for (speed, turn) in [(Float(0.22), Float(0)), (1.65, 0), (3.8, 0), (2.8, 70)] {
            var previous: [Transform]?
            for offset: Float in [-0.001, 0.001] {
                let sample = locomotion(player, at: 12, speed: speed + offset, turn: turn + offset)
                XCTAssertTrue(skin.update(at: 12, track: player, locomotion: sample,
                                          lookTarget: nil, ballAction: nil, hasImpact: false))
                if let previous {
                    for (before, after) in zip(previous, skin.model.jointTransforms) {
                        XCTAssertLessThan(simd_distance(before.translation, after.translation), 0.004)
                        XCTAssertGreaterThan(abs(simd_dot(before.rotation.vector, after.rotation.vector)), 0.999)
                    }
                }
                previous = skin.model.jointTransforms
            }
        }
        let first = locomotion(player, at: 12, speed: 1.4, turn: 100, state: .walk)
        _ = skin.update(at: 12, track: player, locomotion: first, lookTarget: nil, ballAction: nil, hasImpact: false)
        let expected = skin.model.jointTransforms
        let second = locomotion(player, at: 12, speed: 1.4, turn: 100, state: .cut)
        _ = skin.update(at: 12, track: player, locomotion: second, lookTarget: nil, ballAction: nil, hasImpact: false)
        XCTAssertEqual(skin.model.jointTransforms, expected, "A classifier label must never swap the body or pose")
    }

    func testRetargetedTouchRewindAndNumberAnchorsAreExact() throws {
        let (player, skin) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        func seek(_ time: Double) {
            let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                      lookTarget: [9, 0.2, 20], ballAction: action, hasImpact: false))
        }
        seek(13.6)
        let expected = skin.model.jointTransforms
        let front = skin.front.transform
        let back = skin.back.transform
        for time in [3.0, 17, 13.2, 19, 0, 13.6] { seek(time) }
        XCTAssertEqual(skin.model.jointTransforms, expected)
        XCTAssertEqual(skin.front.transform, front)
        XCTAssertEqual(skin.back.transform, back)
        let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
        let anchor = chest * SIMD4(skin.motion.numberAnchors.back, 1)
        XCTAssertLessThan(simd_distance(skin.back.position, SIMD3(anchor.x, anchor.y, anchor.z)), 0.00001)
    }

    func testTouchUsesTheBootOnTheCorrectSideAndDoesNotSwapAtWindowEdges() throws {
        let (player, skin) = try prepare()
        let action = ReplayAthleteBallActionPose(
            kind: .pass, contactTime: 12, kickingLeg: .right, influence: 1,
            kickingHipFlexion: -0.55, kickingKneeFlexion: 0.20, kickingFootPitch: 0,
            supportHipFlexion: 0.03, supportKneeFlexion: 0.20, supportFootPitch: 0,
            supportLateralShift: 0.03
        )
        XCTAssertTrue(skin.update(at: 12, track: player, locomotion: locomotion(player, at: 12, speed: 1.1),
                                  lookTarget: nil, ballAction: action, hasImpact: false))
        let ankles = ["leftAnkle", "rightAnkle"].compactMap { skin.motion.semanticJointIndices[$0] }
        let positiveSide = try XCTUnwrap(ankles.first { position(skin.motion.restPose.modelSpaceTransforms[$0]).x > 0 })
        let negativeSide = try XCTUnwrap(ankles.first { position(skin.motion.restPose.modelSpaceTransforms[$0]).x < 0 })
        XCTAssertGreaterThan(position(skin.pose.modelSpaceTransforms[positiveSide]).z,
                             position(skin.pose.modelSpaceTransforms[negativeSide]).z + 0.20)

        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var previous: [Transform]?
        for time in stride(from: 13.20, through: 14.10, by: 1.0 / 240) {
            let touch = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                      lookTarget: nil, ballAction: touch, hasImpact: false))
            if let previous {
                for (before, after) in zip(previous, skin.model.jointTransforms) {
                    XCTAssertLessThan(simd_distance(before.translation, after.translation), 0.03)
                    XCTAssertGreaterThan(abs(simd_dot(before.rotation.vector, after.rotation.vector)), 0.99)
                }
            }
            previous = skin.model.jointTransforms
        }
    }

    func testRetargetedPoseReusesBuffersAcrossManySeeks() throws {
        let (player, skin) = try prepare()
        _ = skin.update(at: 12, track: player, locomotion: locomotion(player, at: 12, speed: 1.1),
                        lookTarget: nil, ballAction: nil, hasImpact: false)
        let translations = skin.pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let rotations = skin.pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let hierarchy = skin.pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        for time in stride(from: 15.0, through: 0.0, by: -0.11) {
            _ = skin.update(at: time, track: player, locomotion: locomotion(player, at: time, speed: 2, turn: 150),
                            lookTarget: nil, ballAction: nil, hasImpact: false)
        }
        XCTAssertEqual(skin.pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, translations)
        XCTAssertEqual(skin.pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, rotations)
        XCTAssertEqual(skin.pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, hierarchy)
    }

    func testFootballRetargetPoseGallery() throws {
        let (player, skin) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var samples: [[String: Any]] = []
        for (name, time, speed, turn, contact) in [
            ("walk-a", 12.0, Float(1.1), Float(0), false),
            ("walk-b", 12.23, 1.1, 0, false),
            ("cut-left", 12.0, 3.0, -180, false),
            ("cut-right", 12.0, 3.0, 180, false),
            ("pass-prepare", 13.42, 3.6, 0, true),
            ("pass-contact", 13.6, 3.6, 0, true),
            ("pass-release", 13.8, 3.6, 0, true),
            ("run", 12.0, 3.6, 0, false)
        ] {
            let action = contact ? ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time) : nil
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion(player, at: time, speed: speed, turn: turn),
                                      lookTarget: nil, ballAction: action, hasImpact: false))
            samples.append([
                "name": name, "time": time, "groundOffset": -skin.motion.geometry.restMinY,
                "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-FootballRetarget-Poses.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSceneSelectionReleasesOldSkinsAndPOVHidesWearer() throws {
        let (_, _) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        func update(_ playerID: String, mode: ReplayViewMode) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: 12, viewMode: mode,
                                     perspectiveID: playerID, marks: [], showsLaneLens: false,
                                     isDrawing: false, positionalOriginTransform: nil)
        }
        func skins(_ entity: Entity) -> [Entity] {
            let own = entity.name == ReplaySkinnedAthleteProvider.visualRootName ? [entity] : []
            return own + entity.children.flatMap { skins($0) }
        }
        let first = try XCTUnwrap(scenario.players.first)
        let last = try XCTUnwrap(scenario.players.last)
        update(last.id, mode: .tacticalTable)
        XCTAssertEqual(skins(root).count, 1)
        let old = try XCTUnwrap(skins(root).first)
        update(first.id, mode: .tacticalTable)
        XCTAssertNil(old.parent)
        XCTAssertEqual(skins(root).count, 1)
        update(first.id, mode: .firstPerson)
        let wearer = try XCTUnwrap(root.findEntity(named: "player-\(first.id)"))
        XCTAssertTrue(skins(wearer).isEmpty)
        XCTAssertLessThanOrEqual(skins(root).count, PitchSceneFactory.firstPersonDetailedRigLimit)
    }
}
