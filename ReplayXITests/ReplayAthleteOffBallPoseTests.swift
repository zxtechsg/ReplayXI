import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteOffBallPoseTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func player(_ id: String = "offball-red-4", speed: Float = 3.6) -> PlayerTrack {
        .init(id: id, displayName: "Defender", role: "CB", shirtNumber: 4, team: .away,
              isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .zero, facingDegrees: 0),
                .init(time: 10, position: .init(x: 0, z: speed * 10), facingDegrees: 0)
              ])
    }

    private func locomotion(speed: Float = 0, acceleration: Float = 0) -> PlayerLocomotionSample {
        .init(motion: .init(speedMetresPerSecond: speed, distanceTravelled: 0, locomotionPhase: 0.4),
              speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: acceleration,
              turnRateDegreesPerSecond: 0,
              state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: 0))
    }

    private var look: ReplayAthleteLookPose {
        .init(neckYawRadians: 0.35, headYawRadians: 0.48, neckPitchRadians: 0.03, headPitchRadians: 0.05)
    }

    private var kinds: [ReplayAthleteInteractionCue.Kind] {
        [.receive, .pass, .shot, .dribbleTouch, .header, .save]
    }

    private func sample(id: String = "offball-red-4", time: Double = 3,
                        speed: Float = 0, acceleration: Float = 0, action: Float = 0,
                        source: Float = 0, enabled: Bool = true) -> ReplayAthleteOffBallPose.Sample {
        ReplayAthleteOffBallPose.sample(playerID: id, at: time,
            locomotion: locomotion(speed: speed, acceleration: acceleration), look: look,
            actionInfluence: action, sourceFraction: source, enabled: enabled)
    }

    func testIndividualVariationIsBoundedAndExactlySeekStable() {
        let ids = ["red-4", "white-4", "red-6", "white-6"]
        let times = [0.0, 0.25, 1.3, 2.7, 5.2, 8.9]
        for speed: Float in [0, 0.6, 1.6, 3.6, 8] {
            for id in ids {
                let poses = times.map { sample(id: id, time: $0, speed: speed) }
                for index in times.indices.reversed() {
                    let value = sample(id: id, time: times[index], speed: speed)
                    XCTAssertEqual(value, poses[index])
                    XCTAssertLessThanOrEqual(abs(value.chestYaw), 0.16)
                    XCTAssertLessThanOrEqual(abs(value.chestPitch), 0.006)
                    XCTAssertLessThanOrEqual(abs(value.chestRoll), 0.008)
                }
            }
        }
        XCTAssertNotEqual(sample(id: "red-4"), sample(id: "white-4"))
        XCTAssertNotEqual(sample(time: 1), sample(time: 3))
        for step in 0..<600 {
            let first = sample(time: Double(step) / 60)
            let next = sample(time: Double(step + 1) / 60)
            XCTAssertLessThan(abs(first.chestYaw - next.chestYaw), 0.0003)
            XCTAssertLessThan(abs(first.chestPitch - next.chestPitch), 0.0003)
            XCTAssertLessThan(abs(first.chestRoll - next.chestRoll), 0.0003)
        }
    }

    func testTorsoSharingDoesNotAddAnotherHeadTurn() {
        for time in [0.0, 1, 3, 7] {
            let value = sample(time: time)
            let adjusted = value.adjusting(look)
            XCTAssertEqual(value.chestYaw + adjusted.combinedYawRadians, look.combinedYawRadians, accuracy: 0.000001)
            XCTAssertEqual(value.chestPitch + adjusted.combinedPitchRadians, look.combinedPitchRadians, accuracy: 0.000001)
        }
    }

    func testRelaxedArmSetIsSmallIndividualContinuousAndYieldsToRunning() {
        for id in ["red-4", "white-4", "red-6", "white-6"] {
            for step in 0..<300 {
                let value = sample(id: id, time: Double(step) / 60)
                let next = sample(id: id, time: Double(step + 1) / 60)
                XCTAssertEqual(value.armSetWeight, 1)
                XCTAssertEqual(value.bracingWeight, 0)
                for arm in [value.leftArm, value.rightArm] {
                    XCTAssertTrue((Float(0.0749)...0.1251).contains(arm.forward))
                    XCTAssertTrue((Float(0.0799)...0.1201).contains(arm.outward))
                    XCTAssertTrue((Float(0.2999)...0.4001).contains(arm.elbowFlexion))
                }
                XCTAssertLessThan(abs(value.leftArm.elbowFlexion - next.leftArm.elbowFlexion), 0.001)
                XCTAssertLessThan(abs(value.rightArm.elbowFlexion - next.rightArm.elbowFlexion), 0.001)
            }
        }
        XCTAssertNotEqual(sample(id: "red-4").leftArm, sample(id: "white-4").leftArm)
        XCTAssertNotEqual(sample().leftArm, sample().rightArm)
        let source = simd_quatf(angle: 0.8, axis: SIMD3<Float>(1, 0, 0))
        for speed: Float in [2.8, 3.6, 8] {
            let running = sample(speed: speed)
            XCTAssertEqual(running.armSetWeight, 0)
            XCTAssertEqual(running.bracingWeight, 0)
            XCTAssertEqual(running.shoulder(source, isLeft: true).vector, source.vector)
            XCTAssertEqual(running.elbow(source, isLeft: false).vector, source.vector)
        }
        let braking = sample(speed: 3.6, acceleration: -8)
        XCTAssertEqual(braking.armSetWeight, 0)
        XCTAssertEqual(braking.bracingWeight, 1)
        XCTAssertLessThan(braking.shoulderBrace(isLeft: true).angle, 0.09)
    }

    func testProceduralIdleArmsBendWithoutMovingLegsOrWristPose() {
        let player = player(speed: 0)
        func pose(_ enabled: Bool, stationary: Bool = false) -> ReplayAthleteLocomotionPose {
            ReplayAthleteMotion.locomotionPose(for: player, at: 3, locomotion: locomotion(),
                lookTargetWorldPosition: [12, 0.11, 20],
                stationaryPose: stationary ? player.pose(at: 3) : nil,
                presentationPose: player.presentationPose(at: 3), allowsOffBallPose: enabled)
        }
        let before = pose(false), after = pose(true)
        XCTAssertEqual(before.bodyPosition, after.bodyPosition)
        XCTAssertEqual(before.hipsPosition, after.hipsPosition)
        XCTAssertEqual(Array(allRotations(before)[5...10]), Array(allRotations(after)[5...10]))
        XCTAssertGreaterThan(after.leftElbowOrientation.angle, 0.29)
        XCTAssertGreaterThan(after.rightElbowOrientation.angle, 0.29)
        XCTAssertLessThan(after.leftElbowOrientation.angle, 0.41)
        XCTAssertLessThan(after.rightElbowOrientation.angle, 0.41)
        XCTAssertNotEqual(before.leftShoulderOrientation.vector, after.leftShoulderOrientation.vector)
        XCTAssertEqual(before.leftWristOrientation.vector, after.leftWristOrientation.vector)
        XCTAssertEqual(before.rightWristOrientation.vector, after.rightWristOrientation.vector)
        XCTAssertEqual(allRotations(pose(false, stationary: true)), allRotations(pose(true, stationary: true)))
    }

    func testNativeBrakeCorrectionOnlyFillsUnreplacedSourceFraction() {
        XCTAssertEqual(sample(speed: 3.6, acceleration: -8, source: 1).chestPitch, 0.10, accuracy: 0.000001)
        XCTAssertEqual(sample(speed: 3.6, acceleration: 8, source: 1).chestPitch, -0.09, accuracy: 0.000001)
        XCTAssertEqual(sample(speed: 3.6, acceleration: -8, source: 0.3).chestPitch, 0.03, accuracy: 0.000001)
        XCTAssertEqual(sample(speed: 3.6, acceleration: -8, source: 0).chestPitch, 0)
        XCTAssertEqual(sample(speed: 3.6, acceleration: -8, action: 1, source: 1), .zero)
    }

    func testContactCoreDisableAndInvalidInputsPreserveIdentity() {
        for influence: Float in [0.7, 0.8, 1] { XCTAssertEqual(sample(action: influence), .zero) }
        XCTAssertEqual(sample(enabled: false), .zero)
        XCTAssertEqual(sample(time: .nan), .zero)
        XCTAssertEqual(sample(speed: .infinity), .zero)
        XCTAssertEqual(sample(action: .nan), .zero)
        XCTAssertEqual(ReplayAthleteOffBallPose.Sample.zero.adjusting(look), look)
        for boundary: Float in [0.05, 0.7] {
            let a = sample(action: boundary - 0.0001)
            let b = sample(action: boundary + 0.0001)
            XCTAssertLessThan(abs(a.chestYaw - b.chestYaw), 0.000001)
        }
    }

    private func allRotations(_ p: ReplayAthleteLocomotionPose) -> [SIMD4<Float>] {
        [p.bodyOrientation, p.hipsOrientation, p.spineOrientation, p.neckOrientation, p.headOrientation,
         p.leftHipOrientation, p.rightHipOrientation, p.leftKneeOrientation, p.rightKneeOrientation,
         p.leftAnkleOrientation, p.rightAnkleOrientation, p.leftShoulderOrientation, p.rightShoulderOrientation,
         p.leftElbowOrientation, p.rightElbowOrientation, p.leftWristOrientation, p.rightWristOrientation].map(\.vector)
    }

    private func cue(_ kind: ReplayAthleteInteractionCue.Kind, player: PlayerTrack) -> ReplayAthleteInteractionCue {
        .init(playerID: player.id, kind: kind, contactTime: 3, startTime: 2.7, endTime: 3.3,
              kickingLeg: .right,
              contactBallWorldPosition: [0.25, kind == .header ? 1.75 : kind == .save ? 0.9 : 0.11, 11],
              outgoingDirectionWorld: [0, 0, 1])
    }

    func testProceduralLayerDoesNotMoveRootHipsOrLegsAndKeepsEveryContactKind() {
        let player = player(), time = 3.0
        let target: SIMD3<Float> = [12, 0.11, 20]
        func pose(_ enabled: Bool, interaction: ReplayAthleteInteractionCue? = nil) -> ReplayAthleteLocomotionPose {
            ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: locomotion(speed: 3.6),
                lookTargetWorldPosition: target, interaction: interaction,
                presentationPose: player.presentationPose(at: time), allowsOffBallPose: enabled)
        }
        let old = pose(false), current = pose(true)
        XCTAssertEqual(old.bodyPosition, current.bodyPosition)
        XCTAssertEqual(old.hipsPosition, current.hipsPosition)
        XCTAssertEqual(Array(allRotations(old)[5...10]), Array(allRotations(current)[5...10]))
        XCTAssertNotEqual(old.spineOrientation.vector, current.spineOrientation.vector)
        for kind in kinds {
            let contact = cue(kind, player: player)
            XCTAssertEqual(allRotations(pose(false, interaction: contact)), allRotations(pose(true, interaction: contact)))
            XCTAssertEqual(pose(false, interaction: contact).bodyPosition, pose(true, interaction: contact).bodyPosition)
        }
    }

    func testNearAndLowDetailKeepLegsDimensionsFloorHeadLimitsAndRewind() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let player = player()
        let times = [1.0, 2, 3, 4, 5]
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            let chest = skin.motion.numberAnchors.jointIndex
            var saved: [[Transform]] = []
            func update(_ time: Double, enabled: Bool) {
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion(speed: 3.6, acceleration: -6),
                    lookTarget: [20, 0.11, 30], ballAction: nil,
                    presentationPose: player.presentationPose(at: time), allowsOffBallPose: enabled))
            }
            for time in times {
                update(time, enabled: false)
                let baseline = skin.pose
                update(time, enabled: true)
                saved.append(skin.model.jointTransforms)
                XCTAssertNotEqual(skin.pose.rotations[chest].vector, baseline.rotations[chest].vector)
                for side in ["left", "right"] {
                    for joint in ["Hip", "Knee", "Ankle"] {
                        let index = try XCTUnwrap(skin.motion.semanticJointIndices[side + joint])
                        for column in 0..<4 {
                            XCTAssertLessThan(simd_distance(skin.pose.modelSpaceTransforms[index][column],
                                                          baseline.modelSpaceTransforms[index][column]), 0.00001)
                        }
                    }
                    for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                        let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                        let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                        let restLength = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3,
                                                       skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                        let length = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3,
                                                   skin.pose.modelSpaceTransforms[b].columns.3)
                        XCTAssertEqual(length, restLength, accuracy: 0.0002)
                    }
                }
                XCTAssertEqual(skin.pose.scales, baseline.scales)
                XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                            skin.contactSurface.paddingMetres - 0.0001)
                let chestDelta = simd_quatf(skin.pose.modelSpaceTransforms[chest])
                    * simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest]).inverse
                let relative = chestDelta.inverse * simd_quatf(skin.pose.modelSpaceTransforms[head])
                    * simd_quatf(skin.motion.restPose.modelSpaceTransforms[head]).inverse
                let forward = relative.act([0, 0, 1])
                XCTAssertLessThanOrEqual(abs(atan2(forward.x, forward.z)), 70 * .pi / 180 + 0.00001)
                XCTAssertLessThanOrEqual(abs(atan2(-forward.y, hypot(forward.x, forward.z))), 40 * .pi / 180 + 0.00001)
            }
            for index in times.indices.reversed() {
                update(times[index], enabled: true)
                XCTAssertEqual(skin.model.jointTransforms, saved[index])
            }
            for kind in kinds {
                let contact = cue(kind, player: player)
                _ = skin.update(at: 3, track: player, locomotion: locomotion(speed: 3.6),
                    lookTarget: [12, 0.11, 20], ballAction: nil, interaction: contact,
                    presentationPose: player.presentationPose(at: 3), allowsOffBallPose: false)
                let baseline = skin.model.jointTransforms
                _ = skin.update(at: 3, track: player, locomotion: locomotion(speed: 3.6),
                    lookTarget: [12, 0.11, 20], ballAction: nil, interaction: contact,
                    presentationPose: player.presentationPose(at: 3), allowsOffBallPose: true)
                XCTAssertEqual(skin.model.jointTransforms, baseline, "\(detail) \(kind) core unchanged")
            }
        }
    }

    func testNativeIdleUpperBodiesVaryWithoutChangingSourceLegs() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let players = [player("red-4", speed: 0), player("white-4", speed: 0)]
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skins = try players.map { try ReplaySkinnedAthleteProvider.make(for: $0, detail: detail) }
            var baseline: [ReplaySkinnedAthleteMotion.Pose] = []
            var active: [ReplaySkinnedAthleteMotion.Pose] = []
            for index in skins.indices {
                let skin = skins[index], player = players[index]
                for enabled in [false, true] {
                    XCTAssertTrue(skin.update(at: 3, track: player, locomotion: locomotion(),
                        lookTarget: [12, 0.11, 20], ballAction: nil,
                        presentationPose: player.presentationPose(at: 3), allowsOffBallPose: enabled))
                    if enabled { active.append(skin.pose) } else { baseline.append(skin.pose) }
                }
            }
            let chest = skins[0].motion.numberAnchors.jointIndex
            XCTAssertEqual(baseline[0].rotations[chest].vector, baseline[1].rotations[chest].vector)
            XCTAssertNotEqual(active[0].rotations[chest].vector, active[1].rotations[chest].vector)
            for index in skins.indices {
                let motion = skins[index].motion
                for side in ["left", "right"] {
                    let shoulder = try XCTUnwrap(motion.semanticJointIndices[side + "Shoulder"])
                    let elbow = try XCTUnwrap(motion.semanticJointIndices[side + "Elbow"])
                    let wrist = try XCTUnwrap(motion.semanticJointIndices[side + "Wrist"])
                    func point(_ joint: Int) -> SIMD3<Float> {
                        let p = active[index].modelSpaceTransforms[joint].columns.3
                        return [p.x, p.y, p.z]
                    }
                    let upper = point(elbow) - point(shoulder)
                    let lower = point(wrist) - point(elbow)
                    let angle = acos(min(max(simd_dot(simd_normalize(upper), simd_normalize(lower)), -1), 1))
                    XCTAssertGreaterThan(angle, 0.27, "\(detail) \(side) actual elbow bends")
                    XCTAssertLessThan(angle, 0.43, "\(detail) \(side) relaxed, not blocking")
                    XCTAssertNotEqual(active[index].rotations[elbow].vector, baseline[index].rotations[elbow].vector)
                    XCTAssertEqual(active[index].rotations[wrist].vector, baseline[index].rotations[wrist].vector)
                    for (a, b) in [(shoulder, elbow), (elbow, wrist)] {
                        XCTAssertEqual(simd_distance(active[index].modelSpaceTransforms[a].columns.3,
                                                     active[index].modelSpaceTransforms[b].columns.3),
                                       simd_distance(motion.restPose.modelSpaceTransforms[a].columns.3,
                                                     motion.restPose.modelSpaceTransforms[b].columns.3), accuracy: 0.0002)
                    }
                }
                for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                    let joint = try XCTUnwrap(skins[index].motion.semanticJointIndices[name])
                    XCTAssertEqual(active[index].translations[joint], baseline[index].translations[joint])
                    XCTAssertEqual(active[index].rotations[joint].vector, baseline[index].rotations[joint].vector)
                }
            }
        }
    }

    func testNativeImpactDoesNotReceiveOffBallLayer() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        let player = try XCTUnwrap(scenario.player(id: cue.playerID))
        let time = cue.impactTime + 0.3
        let impact = try XCTUnwrap(PlayerRagdollPlayback.sample(for: cue, at: time))
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
            lookTarget: [12, 0.11, 20], ballAction: nil, impact: impact,
            presentationPose: player.presentationPose(at: time), allowsOffBallPose: false))
        let baseline = skin.model.jointTransforms
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
            lookTarget: [12, 0.11, 20], ballAction: nil, impact: impact,
            presentationPose: player.presentationPose(at: time), allowsOffBallPose: true))
        XCTAssertEqual(skin.model.jointTransforms, baseline)
    }
}
