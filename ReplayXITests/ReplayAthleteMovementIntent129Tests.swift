import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Synthetic geometric fixtures for off-ball footwork. These measure rig
/// constraints, not recovered tracking, motion capture or EA FC parity.
@MainActor
final class ReplayAthleteMovementIntent129Tests: XCTestCase {
    override func tearDown() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func player(team: FootballTeam = .away, speed: Float = 0.5,
                        facing: Float = 0) -> PlayerTrack {
        .init(id: "footwork129-\(team.rawValue)", displayName: "Defender", role: "CB", shirtNumber: 4,
              team: team, isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .init(x: 0, z: -speed), facingDegrees: facing),
                .init(time: 2, position: .init(x: 0, z: speed), facingDegrees: facing)
              ])
    }

    private func base(_ player: PlayerTrack, time: Double = 1,
                      phase: Float? = nil) -> ReplayAthleteLocomotionPose {
        ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: player.locomotion(at: time),
            gaitPhase: phase, allowsOffBallPose: false)
    }

    private func chain(_ pose: ReplayAthleteLocomotionPose, side: ReplayAthleteLeg)
        -> (hip: SIMD3<Float>, knee: SIMD3<Float>, ankle: SIMD3<Float>, boot: simd_quatf) {
        let body = pose.bodyOrientation * pose.hipsOrientation
        let hipRotation = body * (side == .left ? pose.leftHipOrientation : pose.rightHipOrientation)
        let kneeRotation = hipRotation * (side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation)
        let boot = kneeRotation * (side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation)
        let hip = pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
            + body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
        let knee = hip + hipRotation.act([0, -0.390, 0])
        return (hip, knee, knee + kneeRotation.act([0, -0.350, 0]), boot)
    }

    private func rotations(_ pose: ReplayAthleteLocomotionPose) -> [SIMD4<Float>] {
        [pose.bodyOrientation, pose.hipsOrientation, pose.spineOrientation, pose.neckOrientation,
         pose.headOrientation, pose.leftHipOrientation, pose.rightHipOrientation,
         pose.leftKneeOrientation, pose.rightKneeOrientation, pose.leftAnkleOrientation,
         pose.rightAnkleOrientation, pose.leftShoulderOrientation, pose.rightShoulderOrientation,
         pose.leftElbowOrientation, pose.rightElbowOrientation,
         pose.leftWristOrientation, pose.rightWristOrientation].map(\.vector)
    }

    private func cue(_ track: PlayerTrack) -> ReplayAthleteInteractionCue {
        .init(playerID: track.id, kind: .pass, contactTime: 1, startTime: 0.68, endTime: 1.42,
              kickingLeg: .right, contactBallWorldPosition: [0.137, 0.11, 0.42],
              outgoingDirectionWorld: [0, 0, 1])
    }

    /// Frozen pre-129 solver equation, independent of the production protected
    /// branch, so contact protection cannot silently adopt a different gait.
    private func legacyLeg(_ pose: ReplayAthleteLocomotionPose, side: ReplayAthleteLeg,
                           sample: ReplayAthleteMovementIntent.Sample) throws -> [SIMD4<Float>] {
        let body = simd_normalize(pose.bodyOrientation * pose.hipsOrientation)
        let oldHips = pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
        let lowered = pose.bodyPosition - SIMD3<Float>(0, 0.020 * sample.readiness, 0)
        let newHips = lowered + pose.bodyOrientation.act(pose.hipsPosition)
        let hip = side == .left ? pose.leftHipOrientation : pose.rightHipOrientation
        let knee = side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation
        let ankle = side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation
        let hipRotation = body * hip
        let kneeRotation = hipRotation * knee
        let footRotation = kneeRotation * ankle
        let offset = body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
        let oldHip = oldHips + offset
        let relative = hipRotation.act([0, -0.390, 0]) + kneeRotation.act([0, -0.350, 0])
        let rotated = simd_quatf(angle: sample.localTravelYaw, axis: [0, 1, 0]).act(relative)
        let target = oldHip + relative + (rotated - relative) * sample.directionalWeight
        let solved = try XCTUnwrap(ReplayAthleteTwoBoneIK.solve(hip: newHips + offset, ankle: target,
            upperLength: 0.390, lowerLength: 0.350, pole: [0, 0, 1]))
        return [
            ReplayAthleteInteractionPose.blend(hip, body.inverse * solved.upperRotation, sample.influence),
            ReplayAthleteInteractionPose.blend(knee, solved.upperRotation.inverse * solved.lowerRotation, sample.influence),
            ReplayAthleteInteractionPose.blend(ankle, solved.lowerRotation.inverse * footRotation, sample.influence)
        ].map(\.vector)
    }

    func testContactProtectionKeepsTheLegacyLegSolveAcrossTheFullActionWindow() throws {
        for team in FootballTeam.allCases {
            for speed: Float in [0.5, 1.5] {
                let track = player(team: team, speed: speed, facing: 90), action = cue(track)
                for time in [0.68, 0.80, 1, 1.2, 1.42] {
                    let original = base(track, time: time)
                    let sample = try XCTUnwrap(ReplayAthleteMovementIntent.sample(track: track, at: time,
                        presentationPose: track.presentationPose(at: time), lookTarget: nil, interaction: action))
                    XCTAssertEqual(sample.contactProtection, 1)
                    let protected = ReplayAthleteMovementIntent.apply(to: original, sample: sample)
                    XCTAssertEqual(protected.bodyPosition,
                                   original.bodyPosition - SIMD3<Float>(0, 0.020 * sample.readiness, 0))
                    for side in [ReplayAthleteLeg.left, .right] {
                        let expected = try legacyLeg(original, side: side, sample: sample)
                        let actual = [side == .left ? protected.leftHipOrientation : protected.rightHipOrientation,
                                      side == .left ? protected.leftKneeOrientation : protected.rightKneeOrientation,
                                      side == .left ? protected.leftAnkleOrientation : protected.rightAnkleOrientation].map(\.vector)
                        for (a, b) in zip(actual, expected) {
                            XCTAssertEqual(a, b, "Recorded preparation must keep the original leg equation bit for bit")
                        }
                    }
                }
                let other = player(team: team == .home ? .away : .home)
                XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: action, track: other, at: 1), 0)
            }
        }
    }

    func testContactPreparationMarginsAreContinuousAndDoNotExtendShortBootCollisionShapes() throws {
        let track = player(speed: 1.5, facing: 90), action = cue(track)
        let margin = ReplayAthleteMovementIntent.contactPreparationMargin
        func pose(_ time: Double) throws -> ReplayAthleteLocomotionPose {
            let sample = try XCTUnwrap(ReplayAthleteMovementIntent.sample(track: track, at: time,
                presentationPose: track.presentationPose(at: time), lookTarget: nil, interaction: action))
            return ReplayAthleteMovementIntent.apply(to: base(track, time: time), sample: sample)
        }
        XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: action, track: track,
            at: action.startTime - margin), 0, accuracy: 0.000001)
        XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: action, track: track,
            at: action.endTime + margin), 0, accuracy: 0.000001)
        for edge in [action.startTime - margin, action.startTime, action.endTime, action.endTime + margin] {
            let a = try pose(edge - 0.00001), b = try pose(edge + 0.00001)
            for (qa, qb) in zip(rotations(a), rotations(b)) {
                XCTAssertLessThan(min(simd_distance(qa, qb), simd_distance(qa, -qb)), 0.002)
            }
            XCTAssertLessThan(simd_distance(a.bodyPosition, b.bodyPosition), 0.0001)
        }
        let ball = BallTrack(keyframes: [.init(time: 0, position: .init(x: 20, z: 20), height: 0.11),
                                        .init(time: 2, position: .init(x: 20, z: 20), height: 0.11)])
        for time in [action.startTime - 0.04, 1.0, action.endTime + 0.04] {
            let contact = ReplayBallPlayerContact(player: track, ball: ball, time: time,
                interaction: action, presentationPose: track.presentationPose(at: time))
            let active = time >= action.startTime && time <= action.endTime
            let expected = hypot(Float(0.018), active ? Float(0.135) : Float(0.180))
            for boot in [contact.leftBoot, contact.rightBoot] {
                XCTAssertEqual(simd_distance(boot.start, boot.end), expected, accuracy: 0.00002)
                XCTAssertEqual(boot.radius, 0.070)
            }
        }
    }

    func testPartialReadinessKeepsBothSolesFixedThroughoutCrouch() {
        for team in FootballTeam.allCases {
            let original = base(player(team: team, speed: 0))
            for ready: Float in [0.02, 0.1, 0.25, 0.5, 0.75, 1] {
                let posed = ReplayAthleteMovementIntent.apply(to: original,
                    sample: .init(localTravelYaw: 0, directionalWeight: 0, readiness: ready))
                XCTAssertEqual(posed.bodyPosition.y, original.bodyPosition.y - ready * 0.02, accuracy: 0.000001)
                XCTAssertEqual(posed.bodyPosition.x, original.bodyPosition.x)
                XCTAssertEqual(posed.bodyPosition.z, original.bodyPosition.z)
                XCTAssertEqual(posed.headOrientation.vector, original.headOrientation.vector)
                for side in [ReplayAthleteLeg.left, .right] {
                    let old = chain(original, side: side), new = chain(posed, side: side)
                    let marker = ReplayAthleteInteractionPose.bootSoleMarker
                    XCTAssertLessThan(simd_distance(new.ankle + new.boot.act(marker),
                                                    old.ankle + old.boot.act(marker)), 0.00003,
                                      "\(team) \(side) partial readiness \(ready) must not sink the sole")
                    XCTAssertEqual(simd_distance(new.hip, new.knee), 0.390, accuracy: 0.00001)
                    XCTAssertEqual(simd_distance(new.knee, new.ankle), 0.350, accuracy: 0.00001)
                }
            }
        }
    }

    func testDirectionalBlendReachesWeightedAnkleGoalOnceAndKeepsBootOrientation() {
        let original = base(player())
        for yaw: Float in [-.pi, -.pi / 2, -0.7, 0.7, .pi / 2, .pi] {
            for weight: Float in [0.02, 0.1, 0.25, 0.5, 0.75, 1] {
                let posed = ReplayAthleteMovementIntent.apply(to: original,
                    sample: .init(localTravelYaw: yaw, directionalWeight: weight, readiness: 0))
                for side in [ReplayAthleteLeg.left, .right] {
                    let old = chain(original, side: side), new = chain(posed, side: side)
                    let rotated = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(old.ankle - old.hip)
                    let goal = old.ankle + (rotated - (old.ankle - old.hip)) * weight
                    XCTAssertLessThan(simd_distance(new.ankle, goal), 0.00003)
                    for axis in [SIMD3<Float>(1, 0, 0), [0, 1, 0], [0, 0, 1]] {
                        XCTAssertLessThan(simd_distance(new.boot.act(axis), old.boot.act(axis)), 0.00003)
                    }
                }
            }
        }
    }

    func testFasterShufflesKeepBootsInTheirOwnLanesAndKneesFacingForward() {
        for team in FootballTeam.allCases {
            let track = player(team: team, speed: 2)
            for step in 0...48 {
                let original = base(track, phase: Float(step) * .pi / 24)
                for yaw: Float in [-.pi / 2, .pi / 2] {
                    let posed = ReplayAthleteMovementIntent.apply(to: original,
                        sample: .init(localTravelYaw: yaw, directionalWeight: 1, readiness: 0, shuffleWeight: 1))
                    let pelvis = posed.bodyOrientation * posed.hipsOrientation
                    let centre = posed.bodyPosition + posed.bodyOrientation.act(posed.hipsPosition)
                    for side in [ReplayAthleteLeg.left, .right] {
                        let leg = chain(posed, side: side)
                        let local = pelvis.inverse.act(leg.ankle - centre)
                        XCTAssertGreaterThanOrEqual(local.x * (side == .left ? -1 : 1), 0.069,
                                                     "\(team) \(side) phase \(step) yaw \(yaw)")
                        let down = simd_normalize(leg.ankle - leg.hip)
                        let bend = leg.knee - leg.hip - down * simd_dot(leg.knee - leg.hip, down)
                        XCTAssertGreaterThan(simd_dot(simd_normalize(bend), pelvis.act([0, 0, 1])), 0.6)
                        XCTAssertEqual(simd_distance(leg.hip, leg.knee), 0.390, accuracy: 0.00001)
                        XCTAssertEqual(simd_distance(leg.knee, leg.ankle), 0.350, accuracy: 0.00001)
                    }
                }
            }
        }
    }

    func testShuffleAdmissionIsContinuousAndDoesNotReplaceGentleWalkOrSprint() throws {
        func sample(speed: Float, facing: Float = 90) throws -> ReplayAthleteMovementIntent.Sample {
            let track = player(speed: speed, facing: facing)
            return try XCTUnwrap(ReplayAthleteMovementIntent.sample(track: track, at: 1,
                presentationPose: track.presentationPose(at: 1), lookTarget: nil))
        }
        XCTAssertEqual(try sample(speed: 0.5).shuffleWeight, 0)
        XCTAssertEqual(try sample(speed: 1.5).shuffleWeight, 1, accuracy: 0.00001)
        XCTAssertEqual(try sample(speed: 1.5, facing: 0).shuffleWeight, 0)
        XCTAssertEqual(try sample(speed: 1.5, facing: 180).shuffleWeight, 0)
        XCTAssertEqual(try sample(speed: 5).influence, 0)
        for speed: Float in [0.08, 0.33, 0.65, 1.3, 2.8, 4.5] {
            let first = try sample(speed: speed - 0.0001), next = try sample(speed: speed + 0.0001)
            XCTAssertLessThan(abs(first.shuffleWeight - next.shuffleWeight), 0.001)
            XCTAssertLessThan(abs(first.directionalWeight - next.directionalWeight), 0.001)
        }
        let first = try sample(speed: 1.5, facing: 179.999)
        let next = try sample(speed: 1.5, facing: -179.999)
        let original = base(player(speed: 1.5))
        let a = ReplayAthleteMovementIntent.apply(to: original, sample: first)
        let b = ReplayAthleteMovementIntent.apply(to: original, sample: next)
        for side in [ReplayAthleteLeg.left, .right] {
            XCTAssertLessThan(simd_distance(chain(a, side: side).ankle, chain(b, side: side).ankle), 0.0002)
        }
    }

    func testNearZeroAdmissionPreservesBoneTwistAndInvalidSamplesFailClosed() throws {
        let track = player(), original = base(track)
        let tiny = ReplayAthleteMovementIntent.apply(to: original,
            sample: .init(localTravelYaw: .pi / 2, directionalWeight: 0.000001, readiness: 0))
        for (a, b) in zip(rotations(original), rotations(tiny)) {
            XCTAssertLessThan(min(simd_distance(a, b), simd_distance(a, -b)), 0.0002)
        }
        for sample in [
            ReplayAthleteMovementIntent.Sample(localTravelYaw: .nan, directionalWeight: 1, readiness: 0),
            .init(localTravelYaw: 0, directionalWeight: .infinity, readiness: 0),
            .init(localTravelYaw: 0, directionalWeight: 0, readiness: .nan),
            .init(localTravelYaw: 0, directionalWeight: 1, readiness: 0, shuffleWeight: .nan)
        ] {
            let value = ReplayAthleteMovementIntent.apply(to: original, sample: sample)
            XCTAssertEqual(rotations(value), rotations(original))
            XCTAssertEqual(value.bodyPosition, original.bodyPosition)
        }
        XCTAssertNil(ReplayAthleteMovementIntent.sample(track: track, at: .nan,
            presentationPose: track.presentationPose(at: 1), lookTarget: nil))
        let largeFacing = try XCTUnwrap(ReplayAthleteMovementIntent.sample(track: track, at: 1,
            presentationPose: .init(position: .zero, facingDegrees: .greatestFiniteMagnitude), lookTarget: nil))
        XCTAssertTrue(largeFacing.localTravelYaw.isFinite)
        XCTAssertTrue(largeFacing.directionalWeight.isFinite)
    }

    func testBothTeamNearAndLowShufflesKeepDimensionsFloorAndExactRewind() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        for team in FootballTeam.allCases {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let track = player(team: team, speed: 1.5, facing: 90)
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                let times = [0.7, 0.85, 1.0, 1.15, 1.3]
                var saved: [[Transform]] = []
                for time in times {
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: [4, 0.11, 0], ballAction: nil, presentationPose: track.presentationPose(at: time)))
                    saved.append(skin.model.jointTransforms)
                    XCTAssertEqual(skin.root.scale, .one)
                    // The source clips retain sub-micrometre float differences
                    // in their unit scales. Footwork must not add visible scale
                    // or stretch; actual segment lengths are checked below.
                    for (actual, rest) in zip(skin.pose.scales, skin.motion.restPose.scales) {
                        XCTAssertLessThanOrEqual(simd_length(actual - rest), 0.000002)
                    }
                    XCTAssertEqual(skin.model.jointTransforms.count, 80)
                    for rotation in skin.pose.rotations {
                        XCTAssertEqual(simd_length(rotation.vector), 1, accuracy: 0.0001)
                    }
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                                skin.contactSurface.paddingMetres - 0.0001)
                    for side in ["left", "right"] {
                        for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                            let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                            let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                            let original = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3,
                                                        skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                            let actual = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3,
                                                      skin.pose.modelSpaceTransforms[b].columns.3)
                            XCTAssertEqual(actual, original, accuracy: 0.0002)
                        }
                    }
                }
                for index in times.indices.reversed() {
                    let time = times[index]
                    _ = skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: [4, 0.11, 0], ballAction: nil, presentationPose: track.presentationPose(at: time))
                    XCTAssertEqual(skin.model.jointTransforms, saved[index], "\(team) \(detail) exact rewind")
                }
            }
        }
    }

    func testBothTeamArticulatedFarShufflesKeepJointContractAndExactRewind() throws {
        try ReplayAthleteHeadProvider.prewarm()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        let tracks = FootballTeam.allCases.map { player(team: $0, speed: 1.5, facing: 90) }
        try ReplayAthleteFactory.prewarm(for: tracks, lods: [.far])
        for track in tracks {
            let far = try ReplayAthleteFactory.make(for: track, lod: .far)
            func update(_ time: Double) {
                ReplayAthleteMotion.update(far, from: track, at: time,
                    lookTargetWorldPosition: [4, 0.11, 0], presentationPose: track.presentationPose(at: time))
            }
            update(1)
            let oldLeft = far.joints[.leftHip].transform
            let oldRight = far.joints[.rightAnkle].transform
            let oldBody = far.joints[.bodyRoot].transform
            for time in [0.7, 1.3, 0.8, 1.2, 1.0] { update(time) }
            XCTAssertEqual(far.joints[.leftHip].transform, oldLeft)
            XCTAssertEqual(far.joints[.rightAnkle].transform, oldRight)
            XCTAssertEqual(far.joints[.bodyRoot].transform, oldBody)
            XCTAssertEqual(far.root.scale, .one)
            XCTAssertEqual(far.metrics.modelEntities, 7)
            XCTAssertEqual(far.joints.articulatedFar?.supportPointCount, 426)
        }
    }
}
