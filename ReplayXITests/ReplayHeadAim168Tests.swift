import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Baseline diagnostic for the rendered cervical chain in the five video studies.
/// The source clips do not provide measured eye or joint angles; these numbers
/// describe our authored replay and native rigs, not ground-truth match motion.
@MainActor
final class ReplayHeadAim168Tests: XCTestCase {
    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private struct Case {
        let scenarioID: String
        let playerIDs: [String]
        let start: Double
    }

    private let cases: [Case] = [
        .init(scenarioID: "final-36-counter-v2", playerIDs: ["arg-11", "fra-5"], start: 7.2),
        .init(scenarioID: "final-81-volley-v2", playerIDs: ["fra-10", "arg-26"], start: 6.1),
        .init(scenarioID: "final-108-rebound-v2", playerIDs: ["arg-10", "fra-4"], start: 2.0),
        .init(scenarioID: "city-45-overlap-header", playerIDs: ["city-42", "liv-4"], start: 5.4),
        .init(scenarioID: "city-57-underlap-cutback", playerIDs: ["city-33", "liv-5"], start: 5.2),
    ]

    private func angles(_ rotation: simd_quatf) -> (yaw: Float, pitch: Float) {
        let forward = simd_normalize(rotation).act([0, 0, 1])
        return (atan2(forward.x, forward.z) * 180 / .pi,
                atan2(-forward.y, hypot(forward.x, forward.z)) * 180 / .pi)
    }

    private func turn(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let dot = abs(simd_dot(simd_normalize(a).vector, simd_normalize(b).vector))
        return 2 * acos(min(max(dot, 0), 1)) * 180 / .pi
    }

    /// Rebuild from transforms actually submitted to RealityKit, as in the
    /// cervical envelope test. A pose buffer alone can miss a writeback bug.
    private func visiblePose(_ skin: ReplaySkinnedAthleteInstance) -> ReplaySkinnedAthleteMotion.Pose {
        var visible = skin.pose
        for (joint, transform) in skin.model.jointTransforms.enumerated() {
            visible.translations[joint] = transform.translation
            visible.rotations[joint] = transform.rotation
            visible.scales[joint] = transform.scale
        }
        skin.motion.rebuildModelSpaceTransforms(in: &visible)
        return visible
    }

    private func matrixGap(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        max(simd_length(a.columns.0 - b.columns.0), simd_length(a.columns.1 - b.columns.1),
            simd_length(a.columns.2 - b.columns.2), simd_length(a.columns.3 - b.columns.3))
    }

    private func runner() -> PlayerTrack {
        PlayerTrack(id: "head-aim-168", displayName: "Head aim audit", role: "RW",
            shirtNumber: 11, team: .home, isGoalkeeper: false,
            keyframes: [
                .init(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                .init(time: 10, position: .init(x: 0, z: 40), facingDegrees: 0),
            ])
    }

    func testOrdinaryAimImprovesNativeHeadAndKeepsBodyFixed() throws {
        try ReplayTripoAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarm()
        let player = runner(), time = 5.0
        let target = SIMD3<Float>(9, 0.4, 25)
        let sample = player.locomotion(at: time)
        let requested = ReplayAthleteMotion.lookPose(for: player, at: time, locomotion: sample,
            targetWorldPosition: target, presentationPose: player.presentationPose(at: time))
        let wanted = (requested.combinedYawRadians * 180 / Float.pi,
                      requested.combinedPitchRadians * 180 / Float.pi)
        var rows: [[String: Any]] = []
        for (name, skin) in [
            ("tripo52-near", try ReplayTripoAthleteProvider.make(for: player, detail: .near)),
            ("tripo52-low", try ReplayTripoAthleteProvider.make(for: player, detail: .lowDetail)),
            ("rocketbox-near", try ReplaySkinnedAthleteProvider.make(for: player, detail: .near)),
        ] {
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
            let restHead = simd_quatf(skin.motion.restPose.modelSpaceTransforms[head])
            func update(control: Bool, interaction: ReplayAthleteInteractionCue? = nil,
                        impact: PlayerRagdollPlayback.Sample? = nil) -> [Transform] {
                skin.disablesCervicalAimForTesting = control
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                    lookTarget: target, ballAction: nil, impact: impact, interaction: interaction,
                    presentationPose: player.presentationPose(at: time)))
                return skin.model.jointTransforms
            }
            let control = update(control: true)
            let sourceVisible = visiblePose(skin)
            let sourceAngles = angles(simd_quatf(sourceVisible.modelSpaceTransforms[head]) * restHead.inverse)
            let aimed = update(control: false)
            let aimedVisible = visiblePose(skin)
            let aimedAngles = angles(simd_quatf(aimedVisible.modelSpaceTransforms[head]) * restHead.inverse)
            let yawBefore = abs(sourceAngles.yaw - wanted.0)
            let yawAfter = abs(aimedAngles.yaw - wanted.0)
            let pitchBefore = abs(sourceAngles.pitch - wanted.1)
            let pitchAfter = abs(aimedAngles.pitch - wanted.1)
            XCTAssertLessThanOrEqual(yawAfter, yawBefore + 0.25, name)
            XCTAssertLessThanOrEqual(pitchAfter, pitchBefore + 0.25, name)
            XCTAssertLessThan(yawAfter + pitchAfter, yawBefore + pitchBefore - 0.3, name)
            XCTAssertGreaterThan(turn(control[neck].rotation, aimed[neck].rotation), 0.01, name)
            XCTAssertGreaterThan(turn(control[head].rotation, aimed[head].rotation), 0.01, name)
            for joint in ["hips", "spine", "chest", "leftShoulder", "rightShoulder",
                          "leftElbow", "rightElbow", "leftWrist", "rightWrist",
                          "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                let index = try XCTUnwrap(skin.motion.semanticJointIndices[joint])
                XCTAssertLessThan(matrixGap(sourceVisible.modelSpaceTransforms[index],
                                            aimedVisible.modelSpaceTransforms[index]), 0.000_01,
                                  "\(name): \(joint) moved with cervical aim")
            }
            rows.append(["rig": name, "requestedYaw": wanted.0, "requestedPitch": wanted.1,
                         "controlYaw": sourceAngles.yaw, "controlPitch": sourceAngles.pitch,
                         "aimedYaw": aimedAngles.yaw, "aimedPitch": aimedAngles.pitch,
                         "neckLocalChangeDegrees": turn(control[neck].rotation, aimed[neck].rotation),
                         "headLocalChangeDegrees": turn(control[head].rotation, aimed[head].rotation)])

            for kind in [ReplayAthleteInteractionCue.Kind.pass, .header] {
                let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: kind,
                    contactTime: time, startTime: time - 0.3, endTime: time + 0.3,
                    kickingLeg: .right, contactBallWorldPosition: [0.15, kind == .header ? 1.6 : 0.11, 20.5],
                    outgoingDirectionWorld: [0, 0, 1], headerSupportLeg: kind == .header ? .right : nil)
                let old = update(control: true, interaction: cue)
                let new = update(control: false, interaction: cue)
                XCTAssertEqual(new, old, "\(name): \(kind) contact core changed")
            }
            let cue = PlayerRagdollCue(playerID: player.id, impactTime: time - 0.5)
            let impact = try XCTUnwrap(PlayerRagdollPlayback.sample(for: cue, at: time))
            XCTAssertEqual(update(control: false, impact: impact), update(control: true, impact: impact),
                           "\(name): impact changed")

            let invalidTarget = SIMD3<Float>(.nan, 0, 0)
            skin.disablesCervicalAimForTesting = true
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                lookTarget: invalidTarget, ballAction: nil, presentationPose: player.presentationPose(at: time)))
            let invalidControl = skin.model.jointTransforms
            skin.disablesCervicalAimForTesting = false
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                lookTarget: invalidTarget, ballAction: nil, presentationPose: player.presentationPose(at: time)))
            XCTAssertEqual(skin.model.jointTransforms, invalidControl,
                           "\(name): invalid target must skip new aim")

            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            let restChest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
            for bearing in stride(from: Float(-180), through: 180, by: 15) {
                let radians = bearing * .pi / 180
                let p = player.presentationPose(at: time).position
                let around = SIMD3<Float>(p.x + sin(radians) * 10, 0.3,
                                          p.z + cos(radians) * 10)
                skin.disablesCervicalAimForTesting = false
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                    lookTarget: around, ballAction: nil, presentationPose: player.presentationPose(at: time)))
                let visible = visiblePose(skin)
                let chestDelta = simd_quatf(visible.modelSpaceTransforms[chest]) * restChest.inverse
                let headDelta = simd_quatf(visible.modelSpaceTransforms[head]) * restHead.inverse
                let relative = angles(simd_normalize(chestDelta.inverse * headDelta))
                XCTAssertLessThanOrEqual(abs(relative.yaw), 70.001, "\(name) at \(bearing)°")
                XCTAssertLessThanOrEqual(abs(relative.pitch), 40.001, "\(name) at \(bearing)°")
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-HeadAim168-OrdinaryAB.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFiveDemoContactFreeHeadAimDiagnostic() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        try ReplayTripoAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarm()

        var rows: [[String: Any]] = []
        var summaries: [[String: Any]] = []
        let frameCount = 15
        let frameStep = 1.0 / 60.0
        for fixture in cases {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == fixture.scenarioID })
            let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.prewarm(
                track: scenario.ball, players: scenario.players, plannedTouches: touches)
            for playerID in fixture.playerIDs {
                let player = try XCTUnwrap(scenario.player(id: playerID))
                // Leave a broad gap around this player's authored contacts.
                for index in 0..<frameCount {
                    let time = fixture.start + Double(index) * frameStep
                    XCTAssertFalse(touches.contains { $0.playerID == playerID && abs($0.time - time) < 0.45 },
                                   "Selected frames must remain clear of the player's contact")
                }
                for (rigName, skin) in [
                    ("tripo52-near", try ReplayTripoAthleteProvider.make(for: player, detail: .near)),
                    ("tripo52-low", try ReplayTripoAthleteProvider.make(for: player, detail: .lowDetail)),
                    ("rocketbox-near", try ReplaySkinnedAthleteProvider.make(for: player, detail: .near)),
                ] {
                    let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
                    let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
                    let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
                    let restChest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
                    let restNeck = simd_quatf(skin.motion.restPose.modelSpaceTransforms[neck])
                    let restHead = simd_quatf(skin.motion.restPose.modelSpaceTransforms[head])
                    var previousHead: simd_quatf?
                    var previousChain: simd_quatf?
                    var maximumHeadStep: Float = 0
                    var maximumChainStep: Float = 0
                    var firstTransforms: [Transform] = []

                    for index in 0..<frameCount {
                        let time = fixture.start + Double(index) * frameStep
                        let presentation = player.presentationPose(at: time)
                        let ball = recording.sample(at: time)
                        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                            ($0.id, $0.presentationPose(at: time))
                        })
                        let target = ReplayAthleteTacticalAttention.target(
                            for: player, at: time, pose: presentation, ball: ball.position,
                            players: scenario.players, poses: poses, contacts: [])
                        let locomotion = player.locomotion(at: time)
                        let requested = ReplayAthleteMotion.lookPose(
                            for: player, at: time, locomotion: locomotion,
                            targetWorldPosition: target, presentationPose: presentation)
                        XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                            lookTarget: target, ballAction: nil, presentationPose: presentation,
                            allowsTrackLocomotionSampling: true))
                        if index == 0 { firstTransforms = skin.model.jointTransforms }
                        let visible = visiblePose(skin)
                        let chestDelta = simd_normalize(simd_quatf(visible.modelSpaceTransforms[chest])
                            * restChest.inverse)
                        let neckDelta = simd_normalize(simd_quatf(visible.modelSpaceTransforms[neck])
                            * restNeck.inverse)
                        let headDelta = simd_normalize(simd_quatf(visible.modelSpaceTransforms[head])
                            * restHead.inverse)
                        let neckRelativeChest = simd_normalize(chestDelta.inverse * neckDelta)
                        let headRelativeChest = simd_normalize(chestDelta.inverse * headDelta)
                        let worldHeading = simd_quatf(angle: presentation.facingDegrees * .pi / 180,
                                                      axis: [0, 1, 0])
                        let worldHeadDelta = simd_normalize(worldHeading * headDelta)
                        let modelAngles = angles(headDelta)
                        let worldAngles = angles(worldHeadDelta)
                        let neckAngles = angles(neckRelativeChest)
                        let chainAngles = angles(headRelativeChest)
                        let headStep = previousHead.map { turn($0, headDelta) } ?? 0
                        let chainStep = previousChain.map { turn($0, headRelativeChest) } ?? 0
                        maximumHeadStep = max(maximumHeadStep, headStep)
                        maximumChainStep = max(maximumChainStep, chainStep)
                        previousHead = headDelta
                        previousChain = headRelativeChest
                        let values: [Float] = [requested.combinedYawRadians, requested.combinedPitchRadians,
                            modelAngles.yaw, modelAngles.pitch, worldAngles.yaw, worldAngles.pitch,
                            neckAngles.yaw, neckAngles.pitch, chainAngles.yaw, chainAngles.pitch,
                            headStep, chainStep]
                        XCTAssertTrue(values.allSatisfy(\.isFinite))
                        rows.append([
                            "scenario": fixture.scenarioID, "player": playerID, "team": player.team.rawValue,
                            "rig": rigName, "frame": index, "time": time,
                            "bodyFacingDegrees": presentation.facingDegrees,
                            "requestedYawDegrees": requested.combinedYawRadians * 180 / .pi,
                            "requestedPitchDegrees": requested.combinedPitchRadians * 180 / .pi,
                            "modelHeadYawDegrees": modelAngles.yaw, "modelHeadPitchDegrees": modelAngles.pitch,
                            "worldHeadYawDegrees": worldAngles.yaw, "worldHeadPitchDegrees": worldAngles.pitch,
                            "neckRelativeChestYawDegrees": neckAngles.yaw,
                            "neckRelativeChestPitchDegrees": neckAngles.pitch,
                            "headRelativeChestYawDegrees": chainAngles.yaw,
                            "headRelativeChestPitchDegrees": chainAngles.pitch,
                            "headFrameTurnDegrees": headStep, "chestRelativeFrameTurnDegrees": chainStep,
                        ])
                    }
                    // Match the existing cervical regression envelope. This
                    // catches large snaps; it is not a realism/comfort rating.
                    XCTAssertLessThanOrEqual(maximumHeadStep, 12,
                        "\(fixture.scenarioID) \(playerID) \(rigName): model-space head snap")
                    XCTAssertLessThanOrEqual(maximumChainStep, 12,
                        "\(fixture.scenarioID) \(playerID) \(rigName): chest-relative head snap")
                    // Out-of-order seeks must reproduce the exact submitted
                    // native joint array, including the head/neck chain.
                    for time in [fixture.start + 1.1, fixture.start + 0.7, fixture.start] {
                        let pose = player.presentationPose(at: time)
                        let ball = recording.sample(at: time)
                        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                            ($0.id, $0.presentationPose(at: time))
                        })
                        let target = ReplayAthleteTacticalAttention.target(
                            for: player, at: time, pose: pose, ball: ball.position,
                            players: scenario.players, poses: poses, contacts: [])
                        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                            lookTarget: target, ballAction: nil, presentationPose: pose,
                            allowsTrackLocomotionSampling: true))
                    }
                    XCTAssertEqual(skin.model.jointTransforms, firstTransforms,
                                   "Absolute seek must reproduce submitted joints exactly")
                    summaries.append([
                        "scenario": fixture.scenarioID, "player": playerID, "rig": rigName,
                        "frames": frameCount, "firstTime": fixture.start,
                        "lastTime": fixture.start + Double(frameCount - 1) * frameStep,
                        "maximumHeadFrameTurnDegrees": maximumHeadStep,
                        "maximumChestRelativeFrameTurnDegrees": maximumChainStep,
                        "absoluteSeekExact": skin.model.jointTransforms == firstTransforms,
                    ])
                }
            }
        }
        XCTAssertEqual(rows.count, cases.count * 2 * 3 * frameCount)
        let payload: [String: Any] = [
            "scope": "Actual near/low RealityKit joint writeback; five authored reference studies; two teams, Tripo near/low and legacy Rocketbox near; 15 consecutive 60 Hz contact-free frames per player. Angles are rig diagnostics, not measured source-video anatomy.",
            "rows": rows, "summaries": summaries,
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-HeadAim168-Baseline.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
