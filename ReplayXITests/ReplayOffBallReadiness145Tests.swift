import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Native regression for no-touch outfield players, using all five real demo
/// recordings. Readiness is authored presentation intent, not measured emotion.
@MainActor
final class ReplayOffBallReadiness145Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage
    private final class Capture { var stages: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:] }
    private struct Candidate {
        let player: PlayerTrack
        let time: Double
        let look: SIMD3<Float>
        let readiness: Float
    }

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testActualFiveDemoReadyArmsSurviveIdleLayerWithLegacyControl() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        var strongestReadiness: Float = 0
        for scenario in FootballReferenceScenarios.all {
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            let touchIDs = Set(recording.touches.map(\.playerID))
            let players = scenario.players.filter { !$0.isGoalkeeper && !touchIDs.contains($0.id) }
            var peaks: [String: Candidate] = [:]
            var samples = 0, settledSamples = 0, readySamples = 0, scanningSamples = 0
            // Exclude the first/last quarter second: clamped route endpoints
            // must not manufacture the only example of a settled athlete.
            for frame in 3..<Int((scenario.duration - 0.25) * 10) {
                let time = Double(frame) / 10
                let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                    ($0.id, $0.presentationPose(at: time))
                })
                let ball = recording.sample(at: time).position
                for player in players {
                    let pose = try XCTUnwrap(poses[player.id])
                    let look = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose,
                        ball: ball, players: scenario.players, poses: poses, contacts: [])
                    let movement = try XCTUnwrap(ReplayAthleteMovementIntent.sample(track: player, at: time,
                        presentationPose: pose, lookTarget: look))
                    samples += 1
                    if player.locomotion(at: time).speedMetresPerSecond < 0.35 { settledSamples += 1 }
                    if movement.readiness > 0.5 { readySamples += 1 }
                    if simd_distance(look, ball) > 0.02 { scanningSamples += 1 }
                    if movement.readiness > (peaks[player.id]?.readiness ?? -1) {
                        peaks[player.id] = .init(player: player, time: time, look: look, readiness: movement.readiness)
                    }
                }
            }
            let candidates = peaks.values.sorted {
                $0.readiness == $1.readiness ? $0.player.id < $1.player.id : $0.readiness > $1.readiness
            }.prefix(2)
            rows.append(["kind": "inventory", "scenario": scenario.id, "sampleCount": samples,
                "settledSamples": settledSamples, "readinessOverHalfSamples": readySamples,
                "scanningSamples": scanningSamples, "noTouchOutfieldPlayers": players.count,
                "highestReadiness": candidates.first?.readiness ?? 0,
                "nativeTouchCount": recording.touches.count, "missedTouches": recording.missedTouchCount])
            for candidate in candidates {
                strongestReadiness = max(strongestReadiness, candidate.readiness)
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let skin = try ReplaySkinnedAthleteProvider.make(for: candidate.player, detail: detail)
                    let legacy = try ReplaySkinnedAthleteProvider.make(for: candidate.player, detail: detail)
                    legacy.disablesOffBallReadyArmsForTesting = true
                    let capture = Capture(), control = Capture()
                    skin.poseStageObserverForTesting = { stage, pose in capture.stages[stage] = pose }
                    legacy.poseStageObserverForTesting = { stage, pose in control.stages[stage] = pose }
                    defer { skin.poseStageObserverForTesting = nil; legacy.poseStageObserverForTesting = nil }
                    let player = candidate.player, time = candidate.time
                    let locomotion = player.locomotion(at: time), pose = player.presentationPose(at: time)
                    func update(_ sampleTime: Double) {
                        for actor in [skin, legacy] {
                            XCTAssertTrue(actor.update(at: sampleTime, track: player,
                                locomotion: player.locomotion(at: sampleTime), lookTarget: candidate.look, ballAction: nil,
                                presentationPose: player.presentationPose(at: sampleTime), allowsTrackLocomotionSampling: true))
                        }
                    }
                    update(time)
                    var before = try XCTUnwrap(capture.stages[.footballRetargetAndContact])
                    var after = try XCTUnwrap(capture.stages[.offBall])
                    var oldAfter = try XCTUnwrap(control.stages[.offBall])
                    skin.motion.rebuildModelSpaceTransforms(in: &before)
                    skin.motion.rebuildModelSpaceTransforms(in: &after)
                    skin.motion.rebuildModelSpaceTransforms(in: &oldAfter)
                    for stage in [Stage.source, .footballRetargetAndContact] {
                        XCTAssertEqual(capture.stages[stage]?.rotations, control.stages[stage]?.rotations)
                        XCTAssertEqual(capture.stages[stage]?.translations, control.stages[stage]?.translations)
                    }
                    let baseLook = ReplayAthleteMotion.lookPose(for: player, at: time, locomotion: locomotion,
                        targetWorldPosition: candidate.look, presentationPose: pose)
                    let offBall = ReplayAthleteOffBallPose.sample(playerID: player.id, at: time,
                        locomotion: locomotion, look: baseLook, actionInfluence: 0,
                        retargetedArmReadiness: candidate.readiness)
                    let oldOffBall = ReplayAthleteOffBallPose.sample(playerID: player.id, at: time,
                        locomotion: locomotion, look: baseLook, actionInfluence: 0)
                    var armRows: [[String: Any]] = []
                    for side in ["left", "right"] {
                        let shoulder = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Shoulder"])
                        let elbow = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Elbow"])
                        let wrist = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Wrist"])
                        func bend(_ value: ReplaySkinnedAthleteMotion.Pose) -> Float {
                            let upper = point(value, elbow) - point(value, shoulder)
                            let lower = point(value, wrist) - point(value, elbow)
                            return acos(min(max(simd_dot(simd_normalize(upper), simd_normalize(lower)), -1), 1)) * 180 / .pi
                        }
                        let oldBend = bend(before), newBend = bend(after), legacyBend = bend(oldAfter)
                        if candidate.readiness > 0.7 {
                            XCTAssertLessThan(abs(oldBend - newBend), abs(oldBend - legacyBend) * 0.35 + 0.001,
                                "Ready arms must retain more of their admitted retarget pose")
                        }
                        if candidate.readiness == 1, offBall.bracingWeight == 0 {
                            XCTAssertEqual(after.rotations[shoulder], before.rotations[shoulder])
                            XCTAssertEqual(after.rotations[elbow], before.rotations[elbow])
                        }
                        let binding = try XCTUnwrap(ReplayAthleteOffBallPose.NativeArmBinding(side: side, motion: skin.motion))
                        let arm = offBall.arm(isLeft: binding.isLeft)
                        armRows.append(["side": side, "nativeIsLeft": binding.isLeft,
                            "retargetElbowBendDegrees": oldBend,
                            "offBallElbowBendDegrees": newBend, "elbowBendLostDegrees": oldBend - newBend,
                            "legacyOffBallElbowBendDegrees": legacyBend,
                            "idleElbowTargetDegrees": arm.elbowFlexion * 180 / .pi,
                            "readyElbowTargetDegrees": Float(0.42 * 180 / Double.pi),
                            "shoulderLocalOverwriteDegrees": angle(before.rotations[shoulder], after.rotations[shoulder]),
                            "elbowLocalOverwriteDegrees": angle(before.rotations[elbow], after.rotations[elbow])])
                    }
                    for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                        let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                        XCTAssertEqual(before.rotations[index], after.rotations[index])
                        XCTAssertEqual(before.translations[index], after.translations[index])
                        XCTAssertEqual(skin.pose.rotations[index], legacy.pose.rotations[index])
                        XCTAssertEqual(skin.pose.modelSpaceTransforms[index], legacy.pose.modelSpaceTransforms[index])
                    }
                    XCTAssertEqual(skin.pose.translations, legacy.pose.translations)
                    XCTAssertEqual(skin.pose.scales, legacy.pose.scales)
                    if candidate.readiness == 0 { XCTAssertEqual(skin.model.jointTransforms, legacy.model.jointTransforms) }
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                        skin.contactSurface.paddingMetres - 0.0001)
                    let saved = skin.model.jointTransforms
                    update(time + 0.3); update(time)
                    XCTAssertEqual(skin.model.jointTransforms, saved)
                    let procedural = ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: locomotion,
                        gaitPhase: player.gaitPhase(at: time), lookTargetWorldPosition: candidate.look, presentationPose: pose)
                    rows.append(["kind": "nativeStages", "scenario": scenario.id, "player": player.id,
                        "team": player.team.rawValue, "detail": String(describing: detail), "time": time,
                        "readiness": candidate.readiness, "speedMetresPerSecond": locomotion.speedMetresPerSecond,
                        "relaxedArmSetWeight": offBall.armSetWeight, "bracingWeight": offBall.bracingWeight,
                        "legacyRelaxedArmSetWeight": oldOffBall.armSetWeight,
                        "ballDistanceMetres": hypot(recording.sample(at: time).position.x - pose.position.x,
                            recording.sample(at: time).position.z - pose.position.z),
                        "arms": armRows,
                        "proceduralLeftElbowDegrees": procedural.leftElbowOrientation.angle * 180 / .pi,
                        "proceduralRightElbowDegrees": procedural.rightElbowOrientation.angle * 180 / .pi])
                }
            }
        }
        XCTAssertGreaterThan(strongestReadiness, 0.5, "Audit must include a real ready off-ball player")
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-OffBallReadiness145-Candidate.json"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testNativeReadyArmAdmissionAndRecoveryStayContinuous() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        for (scenarioID, playerID, centre) in [("city-45-overlap-header", "liv-4", 6.0),
                                             ("city-57-underlap-cutback", "liv-5", 5.9)] {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == scenarioID })
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            XCTAssertFalse(recording.touches.contains { $0.playerID == playerID })
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                let legacy = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                legacy.disablesOffBallReadyArmsForTesting = true
                let arms = try ["leftShoulder", "rightShoulder", "leftElbow", "rightElbow"].map {
                    try XCTUnwrap(skin.motion.semanticJointIndices[$0])
                }
                var previous: [simd_quatf] = [], peakCorrectionStep: Float = 0
                var checkpoints: [(Double, [Transform])] = []
                func update(_ time: Double) {
                    let pose = player.presentationPose(at: time)
                    let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
                    let look = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose,
                        ball: recording.sample(at: time).position, players: scenario.players, poses: poses, contacts: [])
                    for actor in [skin, legacy] {
                        XCTAssertTrue(actor.update(at: time, track: player, locomotion: player.locomotion(at: time),
                            lookTarget: look, ballAction: nil, presentationPose: pose, allowsTrackLocomotionSampling: true))
                    }
                }
                for frame in -144...144 {
                    let time = centre + Double(frame) / 120
                    update(time)
                    let corrections = arms.map { legacy.pose.rotations[$0].inverse * skin.pose.rotations[$0] }
                    if !previous.isEmpty {
                        for index in corrections.indices {
                            peakCorrectionStep = max(peakCorrectionStep, angle(previous[index], corrections[index]))
                        }
                    }
                    previous = corrections
                    XCTAssertEqual(skin.pose.translations, legacy.pose.translations)
                    for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                        let joint = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                        XCTAssertEqual(skin.pose.modelSpaceTransforms[joint], legacy.pose.modelSpaceTransforms[joint])
                    }
                    if frame.isMultiple(of: 24) { checkpoints.append((time, skin.model.jointTransforms)) }
                }
                XCTAssertLessThan(peakCorrectionStep, 1, "The new arm correction must not add a pose snap at 120 Hz")
                for (time, transforms) in checkpoints.reversed() {
                    update(time); XCTAssertEqual(skin.model.jointTransforms, transforms)
                }
                rows.append(["scenario": scenarioID, "player": playerID, "detail": String(describing: detail),
                    "start": centre - 1.2, "end": centre + 1.2, "samples": 289,
                    "maximumCorrectionStepDegreesAt120Hz": peakCorrectionStep,
                    "feetRootAndReverseExact": true])
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-OffBallReadiness145-Continuity.json"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testNativeContactPreparationCoreAndReleaseRemainExactToLegacy() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var checked = 0
        for scenario in FootballReferenceScenarios.all {
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            for touch in recording.touches {
                let player = try XCTUnwrap(scenario.player(id: touch.playerID))
                let cue = ReplayAthleteInteractionCue(playerID: player.id,
                    kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue)),
                    contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                    kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                    outgoingDirectionWorld: touch.outgoingVelocity, headerSupportLeg: touch.headerSupportLeg)
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                    let legacy = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                    legacy.disablesOffBallReadyArmsForTesting = true
                    for time in [cue.startTime + 0.01, cue.contactTime - 0.05, cue.contactTime,
                                 cue.contactTime + 0.05, cue.endTime - 0.01] {
                        let ball = recording.sample(at: time)
                        for actor in [skin, legacy] {
                            XCTAssertTrue(actor.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                lookTarget: ball.position, ballAction: nil, interaction: cue,
                                presentationPose: player.presentationPose(at: time), allowsTrackLocomotionSampling: true))
                        }
                        XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: cue, track: player, at: time), 1)
                        XCTAssertEqual(skin.model.jointTransforms, legacy.model.jointTransforms)
                        XCTAssertEqual(recording.sample(at: time).position, ball.position)
                        XCTAssertEqual(recording.sample(at: time).velocity, ball.velocity)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 270, "All 27 actual contacts, two skins and five contact phases")
    }

    func testReadyArmFadeKeepsZeroReadinessAndContactCoreExact() throws {
        let player = try XCTUnwrap(FootballReferenceScenarios.all.first?.players.first)
        let look = ReplayAthleteLookPose(neckYawRadians: 0.2, headYawRadians: 0.3,
                                        neckPitchRadians: 0.02, headPitchRadians: 0.03)
        func sample(_ readiness: Float, action: Float = 0) -> ReplayAthleteOffBallPose.Sample {
            ReplayAthleteOffBallPose.sample(playerID: player.id, at: 3, locomotion: player.stationaryLocomotion,
                look: look, actionInfluence: action, retargetedArmReadiness: readiness)
        }
        let original = ReplayAthleteOffBallPose.sample(playerID: player.id, at: 3,
            locomotion: player.stationaryLocomotion, look: look, actionInfluence: 0)
        XCTAssertEqual(sample(0), original); XCTAssertEqual(sample(-1), original)
        XCTAssertEqual(sample(1).armSetWeight, 0); XCTAssertEqual(sample(2), sample(1))
        XCTAssertEqual(sample(.nan), .zero)
        for boundary: Float in [0, 1] {
            XCTAssertLessThan(abs(sample(boundary + 0.00001).armSetWeight
                - sample(boundary - 0.00001).armSetWeight), 0.00002)
        }
        for readiness: Float in [0, 0.2, 0.7, 1] {
            let value = sample(readiness)
            XCTAssertEqual(value.chestRotation, original.chestRotation)
            XCTAssertEqual(value.leftArm, original.leftArm); XCTAssertEqual(value.rightArm, original.rightArm)
            for action: Float in [0.7, 0.8, 1] { XCTAssertEqual(sample(readiness, action: action), .zero) }
        }
    }

    private func point(_ pose: ReplaySkinnedAthleteMotion.Pose, _ index: Int) -> SIMD3<Float> {
        let value = pose.modelSpaceTransforms[index].columns.3
        return [value.x, value.y, value.z]
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let delta = simd_normalize(a).inverse * simd_normalize(b)
        return 2 * atan2(simd_length(delta.imag), abs(delta.real)) * 180 / .pi
    }
}
