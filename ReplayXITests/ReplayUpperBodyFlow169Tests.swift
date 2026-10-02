import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayUpperBodyFlow169Tests: XCTestCase {
    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private func locomotion(_ speed: Float) -> PlayerLocomotionSample {
        .init(motion: .init(speedMetresPerSecond: speed, distanceTravelled: 0, locomotionPhase: 0),
              speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
              turnRateDegreesPerSecond: 0,
              state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: 0))
    }

    func testGaitFollowThroughIsBoundedContinuousAndSeekStable() {
        for speed: Float in [0, 0.35, 0.8, 1.65, 3.8, 7.2, 10] {
            let motion = locomotion(speed)
            let phases = (0...720).map { Float($0) * 2 * .pi / 120 }
            let samples = phases.map {
                ReplayAthleteUpperBodyFlow.sample(gaitPhase: $0, locomotion: motion, actionInfluence: 0)
            }
            for index in samples.indices.reversed() {
                let value = samples[index]
                XCTAssertEqual(value, ReplayAthleteUpperBodyFlow.sample(
                    gaitPhase: phases[index], locomotion: motion, actionInfluence: 0))
                XCTAssertLessThanOrEqual(abs(value.chestYaw), 0.05)
                XCTAssertLessThanOrEqual(abs(value.chestPitch), 0.01)
                XCTAssertLessThanOrEqual(abs(value.chestRoll), 0.025)
                for arm in [value.leftArm, value.rightArm] {
                    XCTAssertLessThanOrEqual(abs(arm.shoulderPitch), 0.065)
                    XCTAssertLessThanOrEqual(abs(arm.elbowFlexion), 0.055)
                    XCTAssertLessThanOrEqual(abs(arm.wristPitch), 0.070)
                }
                XCTAssertEqual(value.leftArm.shoulderPitch, -value.rightArm.shoulderPitch, accuracy: 0.000001)
                if index > 0 {
                    XCTAssertLessThan(abs(value.leftArm.wristPitch - samples[index - 1].leftArm.wristPitch), 0.0037)
                    XCTAssertLessThan(abs(value.chestYaw - samples[index - 1].chestYaw), 0.0027)
                }
            }
            if speed <= 0.35 { XCTAssertTrue(samples.allSatisfy(\.isIdentity)) }
        }
        let flow = ReplayAthleteUpperBodyFlow.sample(gaitPhase: 0.12, locomotion: locomotion(7.2), actionInfluence: 0)
        XCTAssertEqual(flow.leftArm.shoulderPitch, 0, accuracy: 0.000001)
        XCTAssertLessThan(flow.leftArm.elbowFlexion, -0.01)
        XCTAssertLessThan(flow.leftArm.wristPitch, -0.03, "Hand should still follow through at the shoulder reversal")
    }

    func testContactReadinessAndInvalidInputsYieldSafely() {
        for action: Float in [0.7, 0.9, 1, .nan, .infinity] {
            XCTAssertEqual(ReplayAthleteUpperBodyFlow.sample(gaitPhase: 0.9, locomotion: locomotion(5),
                actionInfluence: action), .zero)
        }
        XCTAssertEqual(ReplayAthleteUpperBodyFlow.sample(gaitPhase: .nan, locomotion: locomotion(5),
            actionInfluence: 0), .zero)
        XCTAssertEqual(ReplayAthleteUpperBodyFlow.sample(gaitPhase: 0.9, locomotion: locomotion(.nan),
            actionInfluence: 0), .zero)
        XCTAssertEqual(ReplayAthleteUpperBodyFlow.sample(gaitPhase: 0.9, locomotion: locomotion(5),
            actionInfluence: 0, enabled: false), .zero)
        let ready = ReplayAthleteUpperBodyFlow.sample(gaitPhase: 0.9, locomotion: locomotion(5),
            actionInfluence: 0, armReadiness: 1)
        XCTAssertEqual(ready.leftArm, .zero); XCTAssertEqual(ready.rightArm, .zero)
        XCTAssertNotEqual(ready.chestYaw, 0)
        let look = ReplayAthleteLookPose(neckYawRadians: 0.2, headYawRadians: 0.3,
                                        neckPitchRadians: 0.1, headPitchRadians: 0.2)
        let adjusted = ready.adjusting(look)
        XCTAssertEqual(ready.chestYaw + adjusted.combinedYawRadians, look.combinedYawRadians, accuracy: 0.000001)
        XCTAssertEqual(ready.chestPitch + adjusted.combinedPitchRadians, look.combinedPitchRadians, accuracy: 0.000001)
    }

    func testActualRigChainsPreserveLengthsAndExcludeThighAncestors() throws {
        for (resource, profile, expectedCount) in [
            ("ReplayXITripoMotion", ReplaySkinnedAthleteMotion.RigProfile.tripo52, 3),
            ("ReplayXIRocketboxMotion", .rocketbox, 2)
        ] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: resource, withExtension: "json"))
            let motion = try ReplaySkinnedAthleteMotion(data: Data(contentsOf: url), profile: profile)
            let binding = try XCTUnwrap(ReplayAthleteUpperBodyFlow.NativeBinding(motion: motion))
            XCTAssertEqual(binding.torsoJointIndices.count, expectedCount)
            for frame in 0...120 {
                let time = Double(frame) / 60, phase = Float(time) * 2 * .pi * 2
                var before = motion.makePoseBuffer()
                motion.sample(time: time, locomotionEffort: 0.7, gaitPhase: phase, into: &before)
                var after = before
                binding.apply(ReplayAthleteUpperBodyFlow.sample(gaitPhase: phase,
                    locomotion: locomotion(5), actionInfluence: 0), motion: motion, to: &after)
                motion.rebuildModelSpaceTransforms(in: &after)
                XCTAssertEqual(before.translations, after.translations)
                XCTAssertEqual(before.scales, after.scales)
                for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                    let joint = try XCTUnwrap(motion.semanticJointIndices[name])
                    XCTAssertEqual(before.modelSpaceTransforms[joint], after.modelSpaceTransforms[joint], resource + name)
                }
                for side in ["left", "right"] {
                    for (a, b) in [("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                        let first = try XCTUnwrap(motion.semanticJointIndices[side + a])
                        let second = try XCTUnwrap(motion.semanticJointIndices[side + b])
                        func length(_ pose: ReplaySkinnedAthleteMotion.Pose) -> Float {
                            simd_distance(pose.modelSpaceTransforms[first].columns.3, pose.modelSpaceTransforms[second].columns.3)
                        }
                        XCTAssertEqual(length(before), length(after), accuracy: 0.00001)
                    }
                }
            }
        }
    }

    func testTripoBothTeamsNearLowAndProtectedActions() throws {
        try ReplayTripoAthleteProvider.prewarm()
        for team in [FootballTeam.home, .away] {
            for keeper in [false, true] {
                let track = PlayerTrack(id: "flow-\(team)-\(keeper)", displayName: "Flow", role: keeper ? "GK" : "CM",
                    shirtNumber: 8, team: team, isGoalkeeper: keeper, keyframes: [
                        .init(time: 0, position: .zero, facingDegrees: 0),
                        .init(time: 10, position: .init(x: 0, z: 45), facingDegrees: 0)
                    ])
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let skin = try ReplayTripoAthleteProvider.make(for: track, detail: detail)
                    func update(_ time: Double, disabled: Bool, cue: ReplayAthleteInteractionCue? = nil) -> [Transform] {
                        skin.disablesUpperBodyFlowForTesting = disabled
                        XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                            lookTarget: [18, 0.4, 30], ballAction: nil, interaction: cue,
                            presentationPose: track.presentationPose(at: time)))
                        return skin.model.jointTransforms
                    }
                    let baseline = update(3, disabled: true), candidate = update(3, disabled: false)
                    if keeper { XCTAssertEqual(candidate, baseline) }
                    else {
                        for name in ["leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"] {
                            let joint = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                            XCTAssertGreaterThan(simd_distance(candidate[joint].rotation.vector, baseline[joint].rotation.vector), 0.00001)
                        }
                    }
                    _ = update(8, disabled: false)
                    XCTAssertEqual(update(3, disabled: false), candidate)
                    for kind in [ReplayAthleteInteractionCue.Kind.receive, .pass, .shot, .dribbleTouch, .header, .save] {
                        let cue = ReplayAthleteInteractionCue(playerID: track.id, kind: kind,
                            contactTime: 3, startTime: 2.7, endTime: 3.3, kickingLeg: .right,
                            contactBallWorldPosition: [0.2, kind == .header ? 1.65 : kind == .save ? 0.9 : 0.11, 13.8],
                            outgoingDirectionWorld: [0, 0, 1])
                        XCTAssertEqual(update(3, disabled: true, cue: cue), update(3, disabled: false, cue: cue),
                            "\(team) \(detail) \(kind) contact changed")
                    }
                }
            }
        }
    }
}
