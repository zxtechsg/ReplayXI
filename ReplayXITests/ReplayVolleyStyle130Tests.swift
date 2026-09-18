import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayVolleyStyle130Tests: XCTestCase {
    private func player(_ team: FootballTeam = .home) -> PlayerTrack {
        .init(id: "volley-style-\(team.rawValue)", displayName: "Finisher", role: "CF", shirtNumber: 10,
              team: team, isGoalkeeper: false,
              keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                          .init(time: 2, position: .zero, facingDegrees: 0)])
    }

    private func cue(_ player: PlayerTrack, leg: ReplayAthleteLeg = .right,
                     height: Float = 0.50, kind: ReplayAthleteInteractionCue.Kind = .shot,
                     direction: SIMD3<Float> = [0, 0.12, 1]) -> ReplayAthleteInteractionCue {
        .init(playerID: player.id, kind: kind, contactTime: 1, startTime: 0.68, endTime: 1.42,
              kickingLeg: leg, contactBallWorldPosition: [leg == .right ? 0.137 : -0.137, height, 0.42],
              outgoingDirectionWorld: direction,
              supportFootWorldPosition: [leg == .right ? -0.137 : 0.137, 0, 0.035])
    }

    private func foot(_ pose: ReplayAthleteLocomotionPose, side: ReplayAthleteLeg,
                      marker: SIMD3<Float>) -> SIMD3<Float> {
        let hips = pose.bodyOrientation * pose.hipsOrientation
        let hip = hips * (side == .left ? pose.leftHipOrientation : pose.rightHipOrientation)
        let knee = hip * (side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation)
        let ankle = knee * (side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation)
        return pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
            + hips.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            + hip.act([0, -0.390, 0]) + knee.act([0, -0.350, 0]) + ankle.act(marker)
    }

    private func rotations(_ pose: ReplayAthleteLocomotionPose) -> [SIMD4<Float>] {
        [pose.bodyOrientation, pose.hipsOrientation, pose.spineOrientation, pose.neckOrientation,
         pose.headOrientation, pose.leftHipOrientation, pose.rightHipOrientation,
         pose.leftKneeOrientation, pose.rightKneeOrientation, pose.leftAnkleOrientation,
         pose.rightAnkleOrientation, pose.leftShoulderOrientation, pose.rightShoulderOrientation,
         pose.leftElbowOrientation, pose.rightElbowOrientation,
         pose.leftWristOrientation, pose.rightWristOrientation].map(\.vector)
    }

    func testOnlyElevatedShotContactsGainTheStyle() throws {
        let track = player()
        for kind in [ReplayAthleteInteractionCue.Kind.receive, .pass, .dribbleTouch, .header, .save] {
            for height: Float in [0.11, 0.5, 1.1] {
                let action = cue(track, height: height, kind: kind)
                let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: 1, track: track))
                XCTAssertEqual(sample.elevatedShotStyle, .none, "\(kind) @ \(height)")
            }
        }
        for direction in [SIMD3<Float>(0, 0, 1), [0, 0.9, 0.2], [0, -0.2, 1]] {
            let grounded = try XCTUnwrap(ReplayAthleteInteractionPose.sample(
                cue: cue(track, height: 0.11, direction: direction), at: 1, track: track))
            XCTAssertEqual(grounded.elevatedShotStyle, .none,
                           "Launch elevation cannot turn a ground chip into a volley pose")
        }
        let elevated = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: cue(track), at: 1, track: track))
        XCTAssertGreaterThan(elevated.elevatedShotStyle.intensity, 0.9)
        XCTAssertEqual(elevated.elevatedShotStyle.phase, 0)
        XCTAssertEqual(ReplayAthleteElevatedShotStyle.sample(kind: .shot, contactHeight: .nan,
            phase: 0, kickingLeg: .right), .none)
        XCTAssertEqual(ReplayAthleteElevatedShotStyle.sample(kind: .shot, contactHeight: 0.5,
            phase: .infinity, kickingLeg: .right), .none)
        for index in 0...1_200 {
            let style = ReplayAthleteElevatedShotStyle.sample(kind: .shot,
                contactHeight: Float(index) / 1_000, phase: 0, kickingLeg: .right)
            XCTAssertGreaterThanOrEqual(style.intensity, 0)
            XCTAssertLessThanOrEqual(style.intensity, 1)
        }
    }

    func testBothLegsAndTeamsMirrorTheBalanceWithoutChangingAnyFootOrPelvisGoal() throws {
        for team in FootballTeam.allCases {
            let track = player(team)
            let base = ReplayAthleteMotion.locomotionPose(for: track, at: 1)
            for leg in [ReplayAthleteLeg.left, .right] {
                let action = cue(track, leg: leg)
                for time in [0.76, 0.9, 0.96, 1.0, 1.05, 1.2, 1.36] {
                    let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: time, track: track))
                    var unstyled = sample
                    unstyled.elevatedShotStyle = .none
                    let original = ReplayAthleteInteractionPose.apply(to: base, sample: unstyled)
                    let styled = ReplayAthleteInteractionPose.apply(to: base, sample: sample)
                    XCTAssertEqual(styled.bodyPosition, original.bodyPosition)
                    XCTAssertEqual(styled.bodyOrientation.vector, original.bodyOrientation.vector)
                    XCTAssertEqual(styled.hipsPosition, original.hipsPosition)
                    XCTAssertEqual(styled.hipsOrientation.vector, original.hipsOrientation.vector)
                    XCTAssertEqual(styled.neckOrientation.vector, original.neckOrientation.vector)
                    XCTAssertEqual(styled.headOrientation.vector, original.headOrientation.vector)
                    XCTAssertEqual(styled.leftHipOrientation.vector, original.leftHipOrientation.vector)
                    XCTAssertEqual(styled.rightHipOrientation.vector, original.rightHipOrientation.vector)
                    XCTAssertEqual(styled.leftKneeOrientation.vector, original.leftKneeOrientation.vector)
                    XCTAssertEqual(styled.rightKneeOrientation.vector, original.rightKneeOrientation.vector)
                    XCTAssertEqual(styled.leftAnkleOrientation.vector, original.leftAnkleOrientation.vector)
                    XCTAssertEqual(styled.rightAnkleOrientation.vector, original.rightAnkleOrientation.vector)
                    XCTAssertEqual(styled.leftWristOrientation.vector, original.leftWristOrientation.vector)
                    XCTAssertEqual(styled.rightWristOrientation.vector, original.rightWristOrientation.vector)
                    XCTAssertNotEqual(styled.spineOrientation.vector, original.spineOrientation.vector)
                    XCTAssertNotEqual(styled.leftShoulderOrientation.vector, original.leftShoulderOrientation.vector)
                    XCTAssertNotEqual(styled.rightShoulderOrientation.vector, original.rightShoulderOrientation.vector)
                    XCTAssertGreaterThan(sample.elevatedShotStyle.trunkRollRadians * (leg == .right ? 1 : -1), 0)
                }
                let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: 1, track: track))
                let pose = ReplayAthleteInteractionPose.apply(to: base, sample: sample)
                XCTAssertLessThan(simd_distance(foot(pose, side: leg,
                    marker: ReplayAthleteInteractionPose.bootStrikeMarker), sample.strikeSurfaceTarget), 0.000_03)
                XCTAssertLessThan(simd_distance(foot(pose, side: leg.opposite,
                    marker: ReplayAthleteInteractionPose.bootSoleMarker), sample.supportSoleTarget), 0.000_03)
            }
        }
        for phase: Float in [-1, -0.5, 0, 0.5, 1] {
            let left = ReplayAthleteElevatedShotStyle.sample(kind: .shot, contactHeight: 0.5, phase: phase, kickingLeg: .left)
            let right = ReplayAthleteElevatedShotStyle.sample(kind: .shot, contactHeight: 0.5, phase: phase, kickingLeg: .right)
            XCTAssertEqual(left.trunkRollRadians, -right.trunkRollRadians)
            XCTAssertEqual(left.trunkYawRadians, -right.trunkYawRadians)
            XCTAssertEqual(left.trunkPitchRadians, right.trunkPitchRadians)
            XCTAssertEqual(left.arm(striking: true).yaw, -right.arm(striking: true).yaw)
        }
    }

    func testPreparationContactAndRecoveryHaveBoundedDistinctSilhouettes() throws {
        let track = player()
        let action = cue(track)
        let base = ReplayAthleteMotion.locomotionPose(for: track, at: 1)
        let preparation = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: 0.8, track: track))
        let contact = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: 1, track: track))
        let follow = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: 1.25, track: track))
        XCTAssertLessThan(preparation.elevatedShotStyle.phase, 0)
        XCTAssertGreaterThan(follow.elevatedShotStyle.phase, 0)
        XCTAssertLessThan(preparation.elevatedShotStyle.trunkPitchRadians, contact.elevatedShotStyle.trunkPitchRadians)
        XCTAssertGreaterThan(follow.elevatedShotStyle.trunkPitchRadians, contact.elevatedShotStyle.trunkPitchRadians)
        XCTAssertLessThan(preparation.elevatedShotStyle.trunkYawRadians, 0)
        XCTAssertGreaterThan(follow.elevatedShotStyle.trunkYawRadians, 0)
        XCTAssertGreaterThan(preparation.elevatedShotStyle.arm(striking: true).pitch,
                             follow.elevatedShotStyle.arm(striking: true).pitch)
        XCTAssertLessThan(preparation.elevatedShotStyle.arm(striking: false).pitch,
                          follow.elevatedShotStyle.arm(striking: false).pitch)

        for step in 1..<200 {
            let time = action.startTime + (action.endTime - action.startTime) * Double(step) / 200
            let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: action, at: time, track: track))
            let style = sample.elevatedShotStyle
            XCTAssertLessThanOrEqual(abs(style.trunkRollRadians), 0.28)
            XCTAssertLessThanOrEqual(abs(style.trunkPitchRadians), 0.135)
            XCTAssertLessThanOrEqual(abs(style.trunkYawRadians), 0.17)
            let pose = ReplayAthleteInteractionPose.apply(to: base, sample: sample)
            for rotation in rotations(pose) {
                XCTAssertTrue(rotation.x.isFinite && rotation.y.isFinite && rotation.z.isFinite && rotation.w.isFinite)
                XCTAssertEqual(simd_length(rotation), 1, accuracy: 0.000_02)
            }
            let torso = pose.bodyOrientation * pose.hipsOrientation * pose.spineOrientation
            for leg in [ReplayAthleteLeg.left, .right] {
                let shoulder = torso * (leg == .left ? pose.leftShoulderOrientation : pose.rightShoulderOrientation)
                let elbow = shoulder * (leg == .left ? pose.leftElbowOrientation : pose.rightElbowOrientation)
                XCTAssertEqual(simd_length(shoulder.act([0, -0.310, 0])), 0.310, accuracy: 0.000_01)
                XCTAssertEqual(simd_length(elbow.act([0, -0.275, 0])), 0.275, accuracy: 0.000_01)
            }
        }
    }

    func testHeightThresholdsAndCueEdgesRemainContinuous() throws {
        let track = player()
        let base = ReplayAthleteMotion.locomotionPose(for: track, at: 1)
        for threshold: Float in [0.28, 0.55] {
            let a = try XCTUnwrap(ReplayAthleteInteractionPose.sample(
                cue: cue(track, height: threshold - 0.0001), at: 1, track: track))
            let b = try XCTUnwrap(ReplayAthleteInteractionPose.sample(
                cue: cue(track, height: threshold + 0.0001), at: 1, track: track))
            XCTAssertLessThan(abs(a.elevatedShotStyle.intensity - b.elevatedShotStyle.intensity), 0.000_01)
            let first = ReplayAthleteInteractionPose.apply(to: base, sample: a)
            let second = ReplayAthleteInteractionPose.apply(to: base, sample: b)
            XCTAssertLessThan(simd_distance(first.spineOrientation.vector, second.spineOrientation.vector), 0.000_01)
            XCTAssertLessThan(simd_distance(first.rightShoulderOrientation.vector, second.rightShoulderOrientation.vector), 0.000_01)
        }
        let action = cue(track)
        for edge in [action.startTime, action.contactTime, action.endTime] {
            let a = ReplayAthleteInteractionPose.apply(to: base, cue: action, at: edge - 0.0001, track: track)
            let b = ReplayAthleteInteractionPose.apply(to: base, cue: action, at: edge + 0.0001, track: track)
            for (left, right) in zip(rotations(a), rotations(b)) {
                XCTAssertLessThan(simd_distance(left, right), 0.001)
            }
        }
        var previous = ReplayAthleteInteractionPose.apply(to: base, cue: action, at: 0.67, track: track)
        for step in 1...185 {
            let time = 0.67 + Double(step) / 240
            let current = ReplayAthleteInteractionPose.apply(to: base, cue: action, at: time, track: track)
            for (a, b) in zip([previous.spineOrientation, previous.leftShoulderOrientation, previous.rightShoulderOrientation],
                              [current.spineOrientation, current.leftShoulderOrientation, current.rightShoulderOrientation]) {
                XCTAssertLessThan(simd_distance(a.vector, b.vector), 0.035)
            }
            previous = current
        }
    }

    func testStyleRewindsExactlyAtAnyPlaybackOrder() {
        for team in FootballTeam.allCases {
            let track = player(team)
            for leg in [ReplayAthleteLeg.left, .right] {
                let action = cue(track, leg: leg)
                let first = ReplayAthleteMotion.locomotionPose(for: track, at: 1.06, interaction: action)
                for time in [1.42, 0.69, 1.22, 0.84, 1.0, 0.4, 1.8, 1.06] {
                    _ = ReplayAthleteMotion.locomotionPose(for: track, at: time, interaction: action)
                }
                let repeated = ReplayAthleteMotion.locomotionPose(for: track, at: 1.06, interaction: action)
                XCTAssertEqual(rotations(first), rotations(repeated))
                XCTAssertEqual(first.bodyPosition, repeated.bodyPosition)
                XCTAssertEqual(first.hipsPosition, repeated.hipsPosition)
            }
        }
    }

    func testMovingTurningVolleysKeepTheirSupportAtOneWorldPoint() throws {
        let track = player()
        for leg in [ReplayAthleteLeg.left, .right] {
            let action = cue(track, leg: leg)
            for time in [0.95, 0.975, 1, 1.025, 1.05] {
                let presented = PlayerPose(position: .init(x: Float(time - 1) * 0.15, z: Float(time - 1) * 0.6),
                                           facingDegrees: Float(time - 1) * 50)
                let pose = ReplayAthleteMotion.locomotionPose(for: track, at: time,
                    interaction: action, presentationPose: presented)
                let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                let world = SIMD3<Float>(presented.position.x, 0, presented.position.z)
                    + heading.act(foot(pose, side: leg.opposite, marker: ReplayAthleteInteractionPose.bootSoleMarker))
                XCTAssertLessThan(simd_distance(world, try XCTUnwrap(action.supportFootWorldPosition)), 0.000_03)
            }
        }
    }

    func testNativeBothTeamSkinsKeepStrikeContactFloorAndBoneLengths() throws {
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        for team in FootballTeam.allCases {
            let track = player(team)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                for leg in [ReplayAthleteLeg.left, .right] {
                    let action = cue(track, leg: leg)
                    XCTAssertTrue(skin.update(at: 1, track: track, locomotion: track.locomotion(at: 1),
                        lookTarget: action.contactBallWorldPosition, ballAction: nil,
                        interaction: action, presentationPose: track.presentationPose(at: 1)))
                    let marker = try XCTUnwrap(skin.bootMarkers?.markers.first {
                        (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0) == (leg == .left)
                    })
                    let actual4 = skin.pose.modelSpaceTransforms[marker.ankleIndex] * SIMD4(marker.ankleLocalPosition, 1)
                    let actual = SIMD3<Float>(actual4.x, actual4.y - skin.motion.geometry.restMinY, actual4.z)
                    let expected = action.contactBallWorldPosition
                        - simd_normalize(action.outgoingDirectionWorld) * ReplayAthleteInteractionPose.ballRadius
                    XCTAssertLessThanOrEqual(simd_distance(actual, expected), 0.03)
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                               skin.contactSurface.paddingMetres - 0.000_01)
                    for side in ["left", "right"] {
                        let hip = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Hip"])
                        let knee = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Knee"])
                        let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Ankle"])
                        let shoulder = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Shoulder"])
                        let elbow = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Elbow"])
                        let wrist = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Wrist"])
                        for (a, b) in [(hip, knee), (knee, ankle), (shoulder, elbow), (elbow, wrist)] {
                            let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3,
                                                     skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                            let posed = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3,
                                                      skin.pose.modelSpaceTransforms[b].columns.3)
                            XCTAssertEqual(posed, rest, accuracy: 0.000_03, "\(team) \(detail) \(a)→\(b)")
                        }
                    }
                }
            }
        }
    }
}
