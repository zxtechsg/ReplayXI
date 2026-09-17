import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayAthleteInteractionTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func player(moving: Bool = false) -> PlayerTrack {
        PlayerTrack(id: "interaction-test", displayName: "Contact", role: "CM", shirtNumber: 8,
                    team: .home, isGoalkeeper: false,
                    keyframes: [.init(time: 0, position: .init(x: 0, z: moving ? -0.5 : 0), facingDegrees: 0),
                                .init(time: 2, position: .init(x: 0, z: moving ? 0.5 : 0), facingDegrees: 0)])
    }

    private func cue(_ player: PlayerTrack, kind: ReplayAthleteInteractionCue.Kind = .pass,
                     leg: ReplayAthleteLeg = .right, ball: SIMD3<Float>? = nil,
                     direction: SIMD3<Float> = [0, 0, 1]) -> ReplayAthleteInteractionCue {
        ReplayAthleteInteractionCue(playerID: player.id, kind: kind, contactTime: 1,
            startTime: 0.7, endTime: 1.4, kickingLeg: leg,
            contactBallWorldPosition: ball ?? [leg == .right ? 0.137 : -0.137, 0.11, 0.42],
            outgoingDirectionWorld: direction,
            supportFootWorldPosition: [leg == .right ? -0.137 : 0.137, 0, 0.035])
    }

    private func foot(_ pose: ReplayAthleteLocomotionPose, side: ReplayAthleteLeg,
                      marker: SIMD3<Float>) -> SIMD3<Float> {
        let body = pose.bodyOrientation * pose.hipsOrientation
        let hip = body * (side == .left ? pose.leftHipOrientation : pose.rightHipOrientation)
        let knee = hip * (side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation)
        let ankle = knee * (side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation)
        return pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
            + body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            + hip.act([0, -0.390, 0]) + knee.act([0, -0.350, 0]) + ankle.act(marker)
    }

    func testTwoBoneSolveKeepsLengthsAndClampsUnreachableTargets() throws {
        for goal in [SIMD3<Float>(0.2, 0.10, 0.22), [0, 0.8, 0], [3, -2, 1], [0, 0.79999, 0]] {
            let hip = SIMD3<Float>(0, 0.8, 0)
            let solution = try XCTUnwrap(ReplayAthleteTwoBoneIK.solve(
                hip: hip, ankle: goal, upperLength: 0.390, lowerLength: 0.350, pole: [0, 0, 1]))
            XCTAssertEqual(simd_distance(hip, solution.knee), 0.390, accuracy: 0.000_01)
            XCTAssertEqual(simd_distance(solution.knee, solution.ankle), 0.350, accuracy: 0.000_01)
            XCTAssertEqual(simd_length(solution.upperRotation.vector), 1, accuracy: 0.000_01)
            XCTAssertEqual(simd_length(solution.lowerRotation.vector), 1, accuracy: 0.000_01)
        }
        XCTAssertNil(ReplayAthleteTwoBoneIK.solve(hip: .zero, ankle: [.nan, 0, 0],
                                                upperLength: 0.39, lowerLength: 0.35, pole: [0, 0, 1]))
        XCTAssertNil(ReplayAthleteTwoBoneIK.solve(hip: .zero, ankle: .zero,
                                                upperLength: .infinity, lowerLength: 0.35, pole: [0, 0, 1]))
    }

    func testExplicitLeftAndRightTouchesMeetTheActualSphereSurface() throws {
        let player = player()
        for side in [ReplayAthleteLeg.left, .right] {
            let cue = cue(player, leg: side)
            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: 1, interaction: cue)
            let actual = foot(pose, side: side, marker: ReplayAthleteInteractionPose.bootStrikeMarker)
            let expected = cue.contactBallWorldPosition - SIMD3<Float>(0, 0, 0.11)
            XCTAssertLessThan(simd_distance(actual, expected), 0.000_02)
            let support = foot(pose, side: side.opposite, marker: ReplayAthleteInteractionPose.bootSoleMarker)
            XCTAssertLessThan(simd_distance(support, try XCTUnwrap(cue.supportFootWorldPosition)), 0.000_02)
        }
    }

    func testSupportSoleStaysAtOneWorldPointAcrossMovingAndTurningPresentation() throws {
        let player = player(moving: true)
        let cue = cue(player)
        for time in [0.95, 0.975, 1.0, 1.025, 1.05, 1.0] {
            let presented = PlayerPose(position: .init(x: Float(time - 1) * 0.12, z: Float(time - 1) * 0.5),
                                       facingDegrees: Float(time - 1) * 40)
            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: time,
                                                        interaction: cue, presentationPose: presented)
            let local = foot(pose, side: .left, marker: ReplayAthleteInteractionPose.bootSoleMarker)
            let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
            let world = SIMD3<Float>(presented.position.x, 0, presented.position.z) + heading.act(local)
            XCTAssertLessThan(simd_distance(world, try XCTUnwrap(cue.supportFootWorldPosition)), 0.000_03)
        }
    }

    func testInvalidAndOutOfWindowCuesDoNotAlterTheLegacyPose() {
        let player = player()
        let base = ReplayAthleteMotion.locomotionPose(for: player, at: 1)
        let invalid = cue(player, direction: [.nan, 0, 0])
        let result = ReplayAthleteMotion.locomotionPose(for: player, at: 1, interaction: invalid)
        XCTAssertEqual(result.leftHipOrientation.vector, base.leftHipOrientation.vector)
        XCTAssertEqual(result.rightAnkleOrientation.vector, base.rightAnkleOrientation.vector)
        XCTAssertEqual(result.bodyPosition, base.bodyPosition)
        XCTAssertNil(ReplayAthleteInteractionPose.sample(cue: cue(player), at: 0.69, track: player))
        XCTAssertNil(ReplayAthleteInteractionPose.sample(cue: cue(player), at: .infinity, track: player))
        XCTAssertNil(ReplayAthleteInteractionPose.sample(cue: cue(player, direction: .zero), at: 1, track: player))
    }

    func testHeaderAndSaveDoNotRunFootStrikeIK() {
        let player = player()
        let base = ReplayAthleteMotion.locomotionPose(for: player, at: 1)
        for kind in [ReplayAthleteInteractionCue.Kind.header, .save] {
            let result = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
                interaction: cue(player, kind: kind, ball: [0, 1.75, 0.25]))
            if kind == .header {
                XCTAssertEqual(result.leftHipOrientation.vector, base.leftHipOrientation.vector)
                XCTAssertEqual(result.rightKneeOrientation.vector, base.rightKneeOrientation.vector)
                XCTAssertEqual(result.bodyPosition, base.bodyPosition)
            } else {
                // A parry may bend the supporting knees, but never kicks at
                // the high ball. Both soles remain planted on the pitch.
                XCTAssertEqual(foot(result, side: .left, marker: ReplayAthleteInteractionPose.bootSoleMarker).y,
                               0, accuracy: 0.000_03)
                XCTAssertEqual(foot(result, side: .right, marker: ReplayAthleteInteractionPose.bootSoleMarker).y,
                               0, accuracy: 0.000_03)
                XCTAssertEqual(result.bodyPosition.x, base.bodyPosition.x)
                XCTAssertEqual(result.bodyPosition.z, base.bodyPosition.z)
                XCTAssertEqual(result.bodyPosition.y, base.bodyPosition.y - 0.045, accuracy: 0.000_01)
            }
            XCTAssertNotEqual(result.spineOrientation.vector, base.spineOrientation.vector)
            XCTAssertNotEqual(result.leftShoulderOrientation.vector, base.leftShoulderOrientation.vector)
        }
        for height: Float in [0.65, 0.8, 1.0, 1.25, 1.75, 2.0] {
            let result = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
                interaction: cue(player, kind: .save, ball: [0, height, 0.25]))
            for side in [ReplayAthleteLeg.left, .right] {
                XCTAssertEqual(foot(result, side: side, marker: ReplayAthleteInteractionPose.bootSoleMarker).y,
                               0, accuracy: 0.000_03, "A \(height)m parry still needs a planted support stance")
            }
        }
    }

    func testGroundedLoftKeepsBootFlatAndImportedMarkersWithinThreeCentimetres() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let player = player()
        let direction = simd_normalize(SIMD3<Float>(0, 0.65, 0.76))
        let cue = cue(player, direction: direction)
        let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: cue, at: 1, track: player))
        XCTAssertEqual(sample.footOrientation.act([0, 0, 1]).y, 0, accuracy: 0.000_001)
        let expected = cue.contactBallWorldPosition - direction * ReplayAthleteInteractionPose.ballRadius
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                                      lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue))
            let marker = try XCTUnwrap(skin.bootMarkers?.markers.first {
                skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x > 0
            })
            let value = skin.pose.modelSpaceTransforms[marker.ankleIndex] * SIMD4(marker.ankleLocalPosition, 1)
            let actual = SIMD3<Float>(value.x, value.y - skin.motion.geometry.restMinY, value.z)
            XCTAssertLessThanOrEqual(simd_distance(actual, expected), 0.03)
            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                        skin.contactSurface.paddingMetres - 0.000_01)
        }
    }

    func testContactPoseRewindsExactlyAndHasSmoothWindowEdges() {
        let player = player()
        let cue = cue(player)
        let first = ReplayAthleteMotion.locomotionPose(for: player, at: 1, interaction: cue)
        for time in stride(from: 0.68, through: 1.42, by: 1.0 / 120) {
            _ = ReplayAthleteMotion.locomotionPose(for: player, at: time, interaction: cue)
        }
        let second = ReplayAthleteMotion.locomotionPose(for: player, at: 1, interaction: cue)
        XCTAssertEqual(first.bodyPosition, second.bodyPosition)
        XCTAssertEqual(first.leftHipOrientation.vector, second.leftHipOrientation.vector)
        XCTAssertEqual(first.rightAnkleOrientation.vector, second.rightAnkleOrientation.vector)
        for edge in [cue.startTime, cue.endTime] {
            let a = ReplayAthleteMotion.locomotionPose(for: player, at: edge - 0.0001, interaction: cue)
            let b = ReplayAthleteMotion.locomotionPose(for: player, at: edge + 0.0001, interaction: cue)
            XCTAssertLessThan(simd_distance(a.rightHipOrientation.vector, b.rightHipOrientation.vector), 0.001)
            XCTAssertLessThan(simd_distance(a.bodyPosition, b.bodyPosition), 0.001)
        }
    }

    func testSideStepsAndBackpedalRedirectAnklesWithoutTurningTheBoots() throws {
        let player = player(moving: true)
        let time = 1.0
        let base = ReplayAthleteMotion.locomotionPose(for: player, at: time)
        let body = base.bodyOrientation * base.hipsOrientation
        let hip = base.bodyPosition + base.bodyOrientation.act(base.hipsPosition)
            + body.act([0.137, -0.070, 0])
        let oldAnkle = foot(base, side: .right, marker: .zero)
        let oldForward = body * base.rightHipOrientation * base.rightKneeOrientation * base.rightAnkleOrientation
        for facing: Float in [90, -90, 180, -180] {
            let presented = PlayerPose(position: .zero, facingDegrees: facing)
            let sample = try XCTUnwrap(ReplayAthleteMovementIntent.sample(
                track: player, at: time, presentationPose: presented, lookTarget: nil))
            XCTAssertEqual(sample.directionalWeight, 1)
            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: time, presentationPose: presented)
            let expected = hip + simd_quatf(angle: sample.localTravelYaw, axis: [0, 1, 0]).act(oldAnkle - hip)
            XCTAssertLessThan(simd_distance(foot(pose, side: .right, marker: .zero), expected), 0.000_03)
            let forward = pose.bodyOrientation * pose.hipsOrientation * pose.rightHipOrientation
                * pose.rightKneeOrientation * pose.rightAnkleOrientation
            XCTAssertLessThan(simd_distance(forward.act([0, 0, 1]), oldForward.act([0, 0, 1])), 0.000_03)
        }
    }

    func testNearbyBallReadinessCrouchesWithoutMovingStationarySoles() throws {
        let player = player()
        let target = SIMD3<Float>(0, 0.11, 2)
        // Isolate readiness footwork. Off-ball torso/gaze sharing deliberately
        // changes local head rotation and has its own separate pose tests.
        let locomotion = player.locomotion(at: 1)
        let phase = player.gaitPhase(at: 1)
        let base = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
            locomotion: locomotion, gaitPhase: phase, lookTargetWorldPosition: target,
            allowsOffBallPose: false)
        let prepared = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
            locomotion: locomotion, gaitPhase: phase, lookTargetWorldPosition: target,
            presentationPose: .init(position: .zero, facingDegrees: 0), allowsOffBallPose: false)
        XCTAssertEqual(prepared.bodyPosition.y, base.bodyPosition.y - 0.02, accuracy: 0.000_01)
        for side in [ReplayAthleteLeg.left, .right] {
            XCTAssertLessThan(simd_distance(foot(prepared, side: side, marker: ReplayAthleteInteractionPose.bootSoleMarker),
                                            foot(base, side: side, marker: ReplayAthleteInteractionPose.bootSoleMarker)), 0.000_03)
        }
        XCTAssertNotEqual(prepared.leftElbowOrientation.vector, base.leftElbowOrientation.vector)
        XCTAssertEqual(prepared.headOrientation.vector, base.headOrientation.vector)
        XCTAssertNil(ReplayAthleteMovementIntent.sample(track: player, at: 1, presentationPose: nil,
                                                       lookTarget: target))
    }

    func testDirectionWrapIsContinuousAndNativeLegsRemainFiniteDuringRewind() throws {
        let player = player(moving: true)
        let a = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
            presentationPose: .init(position: .zero, facingDegrees: 179.99))
        let b = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
            presentationPose: .init(position: .zero, facingDegrees: -179.99))
        XCTAssertLessThan(simd_distance(foot(a, side: .right, marker: .zero),
                                        foot(b, side: .right, marker: .zero)), 0.0002)
        try ReplaySkinnedAthleteProvider.prewarm()
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        var first: [SIMD4<Float>] = []
        for time in [1.0, 0.7, 1.3, 1.0] {
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                      lookTarget: [1, 0.11, 2], ballAction: nil,
                                      presentationPose: .init(position: .zero, facingDegrees: 120)))
            for rotation in skin.pose.rotations {
                XCTAssertEqual(simd_length(rotation.vector), 1, accuracy: 0.0001)
            }
            if first.isEmpty { first = skin.pose.rotations.map(\.vector) }
        }
        XCTAssertEqual(first, skin.pose.rotations.map(\.vector))
    }

    func testNativeNearAndLowUseActualBootMarkersWithGroundedRewind() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let player = player()
        var report: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let markers = try XCTUnwrap(skin.bootMarkers)
            XCTAssertEqual(markers.markers.count, 2)
            for side in [ReplayAthleteLeg.left, .right] {
                let cue = cue(player, leg: side)
                XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                                          lookTarget: cue.contactBallWorldPosition, ballAction: nil,
                                          interaction: cue))
                let first = skin.pose.rotations.map(\.vector)
                let marker = try XCTUnwrap(markers.markers.first {
                    (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0) == (side == .left)
                })
                let actual4 = skin.pose.modelSpaceTransforms[marker.ankleIndex] * SIMD4(marker.ankleLocalPosition, 1)
                let actual = SIMD3<Float>(actual4.x, actual4.y - skin.motion.geometry.restMinY, actual4.z)
                let expected = cue.contactBallWorldPosition - SIMD3<Float>(0, 0, 0.11)
                let error = simd_distance(actual, expected)
                // The final weighted-mesh floor guard can raise the whole body;
                // retain a tight measured contact budget instead of disabling it.
                XCTAssertLessThan(error, skin.contactSurface.paddingMetres + 0.0001)
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001)
                XCTAssertEqual(actual.z, expected.z, accuracy: 0.0001)
                for time in [1.15, 0.85, 1.0] {
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                              lookTarget: cue.contactBallWorldPosition, ballAction: nil,
                                              interaction: cue))
                }
                XCTAssertEqual(first, skin.pose.rotations.map(\.vector))
                report.append(["detail": String(describing: detail), "leg": side.rawValue,
                               "contactMarkerErrorMetres": error,
                               "markerRestModelPosition": [marker.restModelPosition.x,
                                                            marker.restModelPosition.y, marker.restModelPosition.z]])
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Explicit-Interaction-Contact-Markers.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
