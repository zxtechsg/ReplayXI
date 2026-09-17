import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthletePostureTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private let details: [ReplaySkinnedAthleteProvider.Detail] = [.near, .lowDetail]

    private func player() -> PlayerTrack {
        PlayerTrack(id: "posture-contract", displayName: "Posture", role: "CM", shirtNumber: 8,
                    team: .home, isGoalkeeper: false, keyframes: [
                        .init(time: 0, position: .zero, facingDegrees: 0),
                        .init(time: 20, position: .init(x: 0, z: 22), facingDegrees: 0)
                    ])
    }

    private func skin(_ detail: ReplaySkinnedAthleteProvider.Detail) throws -> ReplaySkinnedAthleteInstance {
        try ReplaySkinnedAthleteProvider.prewarm()
        if detail == .lowDetail { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        return try ReplaySkinnedAthleteProvider.make(for: player(), detail: detail)
    }

    private func locomotion(speed: Float = 1.1, turn: Float = 0, acceleration: Float = 0,
                            time: Double = 4) -> PlayerLocomotionSample {
        .init(motion: player().motion(at: time), speedMetresPerSecond: speed,
              accelerationMetresPerSecondSquared: acceleration, turnRateDegreesPerSecond: turn,
              state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                    turnRateDegreesPerSecond: turn))
    }

    private func source(_ skin: ReplaySkinnedAthleteInstance, sample: PlayerLocomotionSample,
                        time: Double) -> ReplaySkinnedAthleteMotion.Pose {
        var pose = skin.motion.makePoseBuffer()
        let upperEffort = sample.effort * min(max(sample.speedMetresPerSecond / 2.4, 0), 1)
        skin.motion.sample(time: time, locomotionEffort: upperEffort,
                           gaitPhase: player().gaitPhase(at: time), into: &pose)
        return pose
    }

    private func authored(_ sample: PlayerLocomotionSample, time: Double,
                          interaction: ReplayAthleteInteractionCue? = nil) -> ReplayAthleteLocomotionPose {
        ReplayAthleteMotion.locomotionPose(for: player(), at: time, locomotion: sample,
            gaitPhase: player().gaitPhase(at: time), interaction: interaction)
    }

    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        .init(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private func assertRotation(_ actual: simd_quatf, _ expected: simd_quatf,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(abs(simd_dot(simd_normalize(actual).vector, simd_normalize(expected).vector)),
                             0.999999, file: file, line: line)
    }

    func testWalkBrakeAndCutsUseAuthoredChestInTheActualSourceParentFrame() throws {
        let fixtures = [locomotion(), locomotion(acceleration: -6), locomotion(acceleration: 6),
                        locomotion(speed: 3, turn: -180), locomotion(speed: 3, turn: 180)]
        for detail in details {
            let skin = try skin(detail)
            var retargeter = try XCTUnwrap(ReplaySkinnedAthleteFootballPose(motion: skin.motion,
                                                                          bootMarkers: skin.bootMarkers))
            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            let rest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
            for sample in fixtures {
                var pose = source(skin, sample: sample, time: 4)
                let target = authored(sample, time: 4)
                let weight = ReplaySkinnedAthleteFootballPose.influence(locomotion: sample, ballAction: nil)
                XCTAssertEqual(weight, 1)
                let chestTranslation = pose.translations[chest]
                retargeter.apply(target, influence: weight, armInfluence: weight, motion: skin.motion, to: &pose)
                skin.motion.rebuildModelSpaceTransforms(in: &pose)
                let expected = target.bodyOrientation * target.hipsOrientation * target.spineOrientation * rest
                assertRotation(simd_quatf(pose.modelSpaceTransforms[chest]), expected)
                XCTAssertEqual(pose.translations[chest], chestTranslation, "No torso stretching")
            }
        }
    }

    func testZeroInfluencePreservesTheCompleteSampledSource() throws {
        for detail in details {
            let skin = try skin(detail)
            var retargeter = try XCTUnwrap(ReplaySkinnedAthleteFootballPose(motion: skin.motion))
            let sample = locomotion(speed: 3.6)
            var pose = source(skin, sample: sample, time: 4)
            let original = pose
            retargeter.apply(authored(locomotion(turn: 180), time: 4), influence: 0, armInfluence: 0,
                             motion: skin.motion, to: &pose)
            XCTAssertEqual(pose.translations, original.translations)
            XCTAssertEqual(pose.rotations.map(\.vector), original.rotations.map(\.vector))
            XCTAssertEqual(pose.scales, original.scales)
            XCTAssertEqual(pose.modelSpaceTransforms, original.modelSpaceTransforms)
        }
    }

    func testSavePitchIsAppliedOnceAndHeaderAimRemainsOwnedByProvider() throws {
        for detail in details {
            let skin = try skin(detail)
            var retargeter = try XCTUnwrap(ReplaySkinnedAthleteFootballPose(motion: skin.motion,
                                                                          bootMarkers: skin.bootMarkers))
            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            let rest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
            let sample = locomotion()
            for kind in [ReplayAthleteInteractionCue.Kind.save, .header] {
                let cue = ReplayAthleteInteractionCue(playerID: player().id, kind: kind, contactTime: 4,
                    startTime: 3.6, endTime: 4.5, kickingLeg: .right,
                    contactBallWorldPosition: [0.2, kind == .header ? 1.7 : 0.9, 4.8],
                    outgoingDirectionWorld: [0, 0, 1])
                let interaction = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: cue, at: 4,
                                                                                  track: player()))
                var pose = source(skin, sample: sample, time: 4)
                let originalChest = pose.rotations[chest]
                let target = authored(sample, time: 4, interaction: cue)
                retargeter.apply(target, influence: 1, armInfluence: 1, motion: skin.motion,
                                 to: &pose, interaction: interaction)
                skin.motion.rebuildModelSpaceTransforms(in: &pose)
                if kind == .header {
                    assertRotation(pose.rotations[chest], originalChest)
                } else {
                    XCTAssertEqual(interaction.upperBodyPitch, -0.08)
                    let expected = target.bodyOrientation * target.hipsOrientation * target.spineOrientation * rest
                    assertRotation(simd_quatf(pose.modelSpaceTransforms[chest]), expected)
                }
            }
        }
    }

    func testRuntimePosturesKeepFloorBonesAndArmArticulationAcrossRewind() throws {
        for detail in details {
            let skin = try skin(detail)
            let cases: [(Double, Float, Float, Float)] = [
                (2, 1.1, 0, 0), (4, 1.1, 0, -6), (6, 3, -180, 0), (8, 3, 180, 0)
            ]
            var snapshots: [[Transform]] = []
            for (time, speed, turn, acceleration) in cases {
                let sample = locomotion(speed: speed, turn: turn, acceleration: acceleration, time: time)
                XCTAssertTrue(skin.update(at: time, track: player(), locomotion: sample,
                                          lookTarget: nil, ballAction: nil))
                snapshots.append(skin.model.jointTransforms)
                XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                    - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                for side in ["left", "right"] {
                    for names in [("Hip", "Knee"), ("Knee", "Ankle"),
                                  ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                        let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + names.0])
                        let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + names.1])
                        let restLength = simd_distance(position(skin.motion.restPose.modelSpaceTransforms[a]),
                                                       position(skin.motion.restPose.modelSpaceTransforms[b]))
                        let posedLength = simd_distance(position(skin.pose.modelSpaceTransforms[a]),
                                                        position(skin.pose.modelSpaceTransforms[b]))
                        XCTAssertEqual(posedLength, restLength, accuracy: 0.0002, "\(side) \(names)")
                    }
                }
                XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
            }
            for index in cases.indices.reversed() {
                let (time, speed, turn, acceleration) = cases[index]
                let sample = locomotion(speed: speed, turn: turn, acceleration: acceleration, time: time)
                XCTAssertTrue(skin.update(at: time, track: player(), locomotion: sample,
                                          lookTarget: nil, ballAction: nil))
                XCTAssertEqual(skin.model.jointTransforms, snapshots[index])
            }
        }
    }
}
