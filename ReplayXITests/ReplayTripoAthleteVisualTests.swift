import CoreGraphics
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayTripoCaptureCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

@MainActor
final class ReplayTripoAthleteVisualTests: XCTestCase {
    func testCapturesTripoNearAndLowNativePlayerViews() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        defer {
            ReplayTripoAthleteProvider.resetForTesting()
            ReplaySkinnedAthleteProvider.resetForTesting()
        }

        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let keeper = try XCTUnwrap(scenario.player(id: "navy-gk"))
        let homeNear = try ReplayTripoAthleteProvider.make(for: home, detail: .near)
        let awayNear = try ReplayTripoAthleteProvider.make(for: away, detail: .near)
        let keeperNear = try ReplayTripoAthleteProvider.make(for: keeper, detail: .near)
        let awayLow = try ReplayTripoAthleteProvider.make(for: away, detail: .lowDetail)
        let liveInstances = [homeNear, awayNear, keeperNear, awayLow]
        XCTAssertTrue(liveInstances.allSatisfy { $0.motion.rigProfile == .tripo52 && $0.model.jointNames.count == 52 })

        let calibration = try await calibrate()
        let idleTime = 1.25
        for (instance, player, name) in [(homeNear, home, "home"), (awayNear, away, "away"),
                                         (keeperNear, keeper, "keeper")] {
            XCTAssertTrue(update(instance, player: player, time: idleTime, speed: 0, stationary: true))
            try await capture(instance.root, label: "\(name)-near-idle-front", player: player,
                              view: .front, calibration: calibration)
        }
        // Diagnostic separates geometry/normal shading from atlas seams.
        var flat = PhysicallyBasedMaterial()
        flat.baseColor = .init(tint: .white)
        flat.roughness = .init(floatLiteral: 0.78)
        let original = try XCTUnwrap(homeNear.model.model)
        var withoutAtlas = original
        withoutAtlas.materials = [flat]
        homeNear.model.model = withoutAtlas
        try await capture(homeNear.root, label: "home-near-idle-flat-material-diagnostic", player: home,
                          view: .front, calibration: calibration)
        homeNear.model.model = original
        let savedJoints = homeNear.model.jointTransforms
        homeNear.model.jointTransforms = homeNear.motion.restPose.translations.indices.map { index in
            Transform(scale: homeNear.motion.restPose.scales[index],
                      rotation: homeNear.motion.restPose.rotations[index],
                      translation: homeNear.motion.restPose.translations[index])
        }
        try await capture(homeNear.root, label: "home-near-rest-pose-diagnostic", player: home,
                          view: .front, calibration: calibration)
        homeNear.model.jointTransforms = savedJoints
        XCTAssertTrue(update(homeNear, player: home, time: idleTime, speed: 0, stationary: true))
        try await capture(homeNear.root, label: "home-near-idle-back-number-\(home.shirtNumber)",
                          player: home, view: .back, calibration: calibration)

        let runTime = 13.6
        XCTAssertTrue(update(homeNear, player: home, time: runTime, speed: 3.6, stationary: false))
        try await capture(homeNear.root, label: "home-near-run-side", player: home,
                          view: .side, calibration: calibration)
        try await capture(homeNear.root, label: "home-near-run-front", player: home,
                          view: .front, calibration: calibration)
        XCTAssertTrue(update(awayLow, player: away, time: runTime, speed: 3.6, stationary: false))
        try await capture(awayLow.root, label: "away-low-run-front", player: away,
                          view: .front, calibration: calibration)

        // Keep every native skinned root alive until all renderer work completes.
        withExtendedLifetime(liveInstances) {}
    }

    func testCapturesTripoDiversity172NativeViews() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        defer {
            ReplayTripoAthleteProvider.resetForTesting()
            ReplaySkinnedAthleteProvider.resetForTesting()
        }

        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-lb"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let keeper = try XCTUnwrap(scenario.player(id: "navy-gk"))
        let homeNear = try ReplayTripoAthleteProvider.makeDiverse(for: home, detail: .near)
        let awayNear = try ReplayTripoAthleteProvider.makeDiverse(for: away, detail: .near)
        let keeperNear = try ReplayTripoAthleteProvider.makeDiverse(for: keeper, detail: .near)
        let awayLow = try ReplayTripoAthleteProvider.makeDiverse(for: away, detail: .lowDetail)
        let liveInstances = [homeNear, awayNear, keeperNear, awayLow]
        XCTAssertTrue(liveInstances.allSatisfy { $0.motion.rigProfile == .tripo52 && $0.model.jointNames.count == 52 })

        let calibration = try await calibrate()
        let idleTime = 1.25
        XCTAssertTrue(update(homeNear, player: home, time: idleTime, speed: 0, stationary: true))
        try await capture(homeNear.root, label: "diversity172-home-near-idle-front", player: home,
                          view: .front, calibration: calibration)
        XCTAssertTrue(update(awayNear, player: away, time: idleTime, speed: 0, stationary: true))
        try await capture(awayNear.root, label: "diversity172-away-near-idle-front", player: away,
                          view: .front, calibration: calibration)
        XCTAssertTrue(update(keeperNear, player: keeper, time: idleTime, speed: 0, stationary: true))
        try await capture(keeperNear.root, label: "diversity172-keeper-near-idle-back-number-\(keeper.shirtNumber)",
                          player: keeper, view: .back, calibration: calibration)

        let runTime = 13.6
        XCTAssertTrue(update(homeNear, player: home, time: runTime, speed: 3.6, stationary: false))
        try await capture(homeNear.root, label: "diversity172-home-near-run-three-quarter", player: home,
                          view: .threeQuarter, calibration: calibration)
        XCTAssertTrue(update(awayLow, player: away, time: runTime, speed: 3.6, stationary: false))
        try await capture(awayLow.root, label: "diversity172-away-low-run-front", player: away,
                          view: .front, calibration: calibration)

        let headAimTime = 1.25
        let headAimTarget: SIMD3<Float> = [1.8, 1.58, 3.2]
        XCTAssertTrue(homeNear.update(at: headAimTime, track: home,
            locomotion: home.locomotion(at: headAimTime), lookTarget: nil,
            ballAction: nil, presentationPose: home.presentationPose(at: headAimTime),
            allowsTrackLocomotionSampling: true))
        let head = try XCTUnwrap(homeNear.motion.semanticJointIndices["head"])
        let controlHead = homeNear.model.jointTransforms[head]
        XCTAssertTrue(homeNear.update(at: headAimTime, track: home,
            locomotion: home.locomotion(at: headAimTime), lookTarget: headAimTarget,
            ballAction: nil, presentationPose: home.presentationPose(at: headAimTime),
            allowsTrackLocomotionSampling: true))
        XCTAssertNotEqual(homeNear.model.jointTransforms[head], controlHead,
                          "The close-up capture must show the new head aim response")
        try await capture(homeNear.root, label: "diversity172-home-near-head-aim-close", player: home,
                          view: .front, calibration: calibration, closeUp: true)

        withExtendedLifetime(liveInstances) {}
    }

    /// Matched native body-local crop; only the cervical aim switch changes.
    func testReferenceHeadAim168CloseUpBeforeAfter() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        let calibration = try await calibrate()
        for (scenarioID, playerID, time) in [
            ("final-36-counter-v2", "arg-11", 7.2),
            ("final-81-volley-v2", "fra-10", 6.1),
        ] {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == scenarioID })
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.prewarm(
                track: scenario.ball, players: scenario.players, plannedTouches: touches)
            let skin = try ReplayTripoAthleteProvider.make(for: player, detail: .near)
            let pose = player.presentationPose(at: time)
            let ball = recording.sample(at: time)
            let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                ($0.id, $0.presentationPose(at: time))
            })
            let target = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose,
                ball: ball.position, players: scenario.players, poses: poses, contacts: [])
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            var controlHead: Transform?
            for control in [true, false] {
                skin.disablesCervicalAimForTesting = control
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: target, ballAction: nil, presentationPose: pose,
                    allowsTrackLocomotionSampling: true))
                if control { controlHead = skin.model.jointTransforms[head] }
                else { XCTAssertNotEqual(skin.model.jointTransforms[head], try XCTUnwrap(controlHead)) }
                try await capture(skin.root,
                    label: "head-aim168-\(scenarioID)-\(playerID)-\(control ? "control" : "aimed")-close",
                    player: player, view: .front, calibration: calibration, closeUp: true)
            }
        }
    }

    /// Native A/B evidence, not an automatic judgement of animation quality.
    /// Same contacts, latest cervical aim, source phase, view, skin and lights.
    func testUpperBodyFlow169RunAndTurnBeforeAfter() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer {
            ReplayTripoAthleteProvider.resetForTesting()
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        try ReplayTripoAthleteProvider.prewarm()
        let calibration = try await calibrate()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.missedTouchCount, 0)
        var rows: [[String: Any]] = []
        for (playerID, turning) in [("arg-11", false), ("fra-5", true)] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let cues = try recording.touches.filter { $0.playerID == playerID }.map {
                ReplayAthleteInteractionCue(playerID: playerID,
                    kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                    contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                    kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                    outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
            }
            func cue(_ time: Double) -> ReplayAthleteInteractionCue? {
                cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                    .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
            }
            func target(_ time: Double) -> SIMD3<Float> {
                let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
                return ReplayAthleteTacticalAttention.target(for: player, at: time, pose: player.presentationPose(at: time),
                    ball: recording.sample(at: time).position, players: scenario.players, poses: poses, contacts: cues)
            }
            // Pick a visible phase from the real route. The criterion uses only
            // telemetry and the flow descriptor, never rendered image scoring.
            var chosen: Double?, bestScore: Float = 0
            for frame in 15..<Int((scenario.duration - 0.6) * 30) {
                let time = Double(frame) / 30, locomotion = player.locomotion(at: time)
                guard locomotion.speedMetresPerSecond > 1.8, cue(time) == nil, cue(time + 0.1) == nil else { continue }
                let movement = ReplayAthleteMovementIntent.sample(track: player, at: time,
                    presentationPose: player.presentationPose(at: time), lookTarget: target(time), interaction: cue(time))
                let flow = ReplayAthleteUpperBodyFlow.sample(gaitPhase: player.gaitPhase(at: time),
                    locomotion: locomotion, actionInfluence: 0, armReadiness: movement?.readiness ?? 0)
                let visible = abs(flow.leftArm.shoulderPitch) + abs(flow.leftArm.wristPitch)
                let turn = abs(locomotion.turnRateDegreesPerSecond)
                let score = visible * (turning ? turn : locomotion.speedMetresPerSecond / (1 + turn / 40))
                if score > bestScore { chosen = time; bestScore = score }
            }
            let centre = try XCTUnwrap(chosen, "No eligible \(playerID) \(turning ? "turn" : "run") sample")
            XCTAssertGreaterThan(bestScore, 0)
            if turning { XCTAssertGreaterThan(abs(player.locomotion(at: centre).turnRateDegreesPerSecond), 10) }
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplayTripoAthleteProvider.make(for: player, detail: detail)
                let retained = skin
                for (frame, time) in [centre, centre + 1.0 / 12].enumerated() {
                    let locomotion = player.locomotion(at: time)
                    let attention = target(time), presentation = player.presentationPose(at: time)
                    let interaction = cue(time)
                    var controlJoints: [Transform] = [], controlPose: ReplaySkinnedAthleteMotion.Pose?
                    for control in [true, false] {
                        skin.disablesUpperBodyFlowForTesting = control
                        XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                            lookTarget: attention, ballAction: nil, interaction: interaction,
                            presentationPose: presentation, allowsTrackLocomotionSampling: true))
                        if control {
                            controlJoints = skin.model.jointTransforms
                            controlPose = skin.pose
                        } else {
                            let old = try XCTUnwrap(controlPose)
                            XCTAssertNotEqual(skin.model.jointTransforms, controlJoints)
                            for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                                let joint = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                                XCTAssertEqual(skin.pose.modelSpaceTransforms[joint], old.modelSpaceTransforms[joint])
                            }
                            XCTAssertEqual(skin.pose.translations, old.translations)
                            XCTAssertEqual(skin.pose.scales, old.scales)
                        }
                        let variant = control ? "before" : "after"
                        let detailName = detail == .near ? "near" : "low"
                        let label = "flow169-\(playerID)-\(turning ? "turn" : "run")-\(detailName)-f\(frame)-\(variant)"
                        try await capture(skin.root, label: label, player: player, view: .threeQuarter,
                                          calibration: calibration, closeUp: true)
                        rows.append(["label": label, "time": time, "gaitPhase": player.gaitPhase(at: time),
                            "speed": locomotion.speedMetresPerSecond, "turnDegreesPerSecond": locomotion.turnRateDegreesPerSecond,
                            "detail": detailName, "player": playerID, "team": player.team.rawValue,
                            "variant": variant, "hasPreparedContact": interaction != nil,
                            "cervicalAimEnabled": !skin.disablesCervicalAimForTesting])
                    }
                }
                withExtendedLifetime(retained) {}
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-UpperBodyFlow169-VisualFrames.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppearance170BothTeamsAndRecoveryRunNativeViews() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedAppearanceCount, 4)
        let calibration = try await calibrate()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        var retained: [ReplaySkinnedAthleteInstance] = []
        for team in FootballTeam.allCases {
            let source = try XCTUnwrap(scenario.players.first { $0.team == team && !$0.isGoalkeeper })
            for number in team == .home ? [5, 6, 7, 8] : [8, 9, 5, 6] {
                let player = PlayerTrack(id: "appearance-\(team.rawValue)-\(number)", displayName: "Fictional appearance",
                    role: source.role, shirtNumber: number, team: team, isGoalkeeper: false, keyframes: source.keyframes)
                let skin = try ReplayTripoAthleteProvider.make(for: player)
                retained.append(skin)
                XCTAssertTrue(update(skin, player: player, time: 1.25, speed: 0, stationary: true))
                let label = "appearance170-\(ReplayTripoAppearance.palette(for: player).rawValue)-\(team.rawValue)"
                try await capture(skin.root, label: label, player: player, view: .front,
                                  calibration: calibration, closeUp: true)
            }
        }
        let player = try XCTUnwrap(scenario.player(id: "fra-5"))
        let skin = try ReplayTripoAthleteProvider.make(for: player)
        retained.append(skin)
        // This isolates the two source clips, not the scene's contact retarget.
        XCTAssertTrue(update(skin, player: player, time: 2, speed: 2, stationary: false))
        skin.front.isEnabled = false; skin.back.isEnabled = false
        for phase: Float in [0.85, 3.9] {
            for weight: Float in [0, 1] {
                var pose = skin.motion.makePoseBuffer()
                skin.motion.sample(time: 2, locomotionEffort: 1, gaitPhase: phase,
                                   slowRunWeight: weight, into: &pose)
                skin.contactSurface.raiseAboveFloor(skin.motion.geometry.restMinY + skin.contactSurface.paddingMetres,
                                                    in: &pose)
                skin.model.jointTransforms = pose.translations.indices.map {
                    Transform(scale: pose.scales[$0], rotation: pose.rotations[$0], translation: pose.translations[$0])
                }
                try await capture(skin.root, label: "recovery170-phase\(phase)-\(weight == 0 ? "source" : "relaxed")",
                    player: player, view: .threeQuarter, calibration: calibration)
            }
        }
        withExtendedLifetime(retained) {}
    }

    /// Fixed-camera native frames for slow A/B review of one gait cycle.
    /// This isolates source arms, not a recovered match pose or scene playback.
    func testRecovery170NativeCycleForSlowReview() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        let calibration = try await calibrate()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first {
            $0.id == "final-36-counter-v2"
        })
        let player = try XCTUnwrap(scenario.player(id: "fra-5"))
        let skin = try ReplayTripoAthleteProvider.make(for: player)
        XCTAssertTrue(update(skin, player: player, time: 2, speed: 2, stationary: false))
        skin.front.isEnabled = false; skin.back.isEnabled = false
        var pose = skin.motion.makePoseBuffer()
        for weight: Float in [0, 1] {
            for frame in 0..<24 {
                let phase = Float(frame) / 24 * 2 * .pi
                skin.motion.sample(time: 2, locomotionEffort: 1, gaitPhase: phase,
                                   slowRunWeight: weight, into: &pose)
                skin.contactSurface.raiseAboveFloor(
                    skin.motion.geometry.restMinY + skin.contactSurface.paddingMetres, in: &pose)
                skin.model.jointTransforms = pose.translations.indices.map {
                    Transform(scale: pose.scales[$0], rotation: pose.rotations[$0],
                              translation: pose.translations[$0])
                }
                let variant = weight == 0 ? "source" : "relaxed"
                try await capture(skin.root,
                    label: String(format: "recovery170-cycle-%@-%03d", variant, frame),
                    player: player, view: .threeQuarter, calibration: calibration)
            }
        }
        withExtendedLifetime(skin) {}
    }

    private enum View {
        case front, back, side, threeQuarter
    }

    private func update(_ instance: ReplaySkinnedAthleteInstance, player: PlayerTrack,
                        time: Double, speed: Float, stationary: Bool) -> Bool {
        let state = PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: 0)
        let sample = PlayerLocomotionSample(
            motion: PlayerMotionState(speedMetresPerSecond: speed, distanceTravelled: 0,
                                     locomotionPhase: player.gaitPhase(at: time)),
            speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
            turnRateDegreesPerSecond: 0, state: state)
        return instance.update(at: time, track: player, locomotion: sample,
            lookTarget: nil, ballAction: nil,
            stationaryPose: stationary ? player.presentationPose(at: time) : nil,
            allowsOffBallPose: false)
    }

    private func capture(_ avatar: Entity, label: String, player: PlayerTrack, view: View,
                         calibration: ReplayRealityRendererAudit.Calibration,
                         closeUp: Bool = false) async throws {
        let target = SIMD3<Float>(0, closeUp ? 1.40 : 0.91, 0)
        let position: SIMD3<Float>
        let keyPosition: SIMD3<Float>
        let fillPosition: SIMD3<Float>
        switch view {
        case .front:
            position = closeUp ? [0, 1.55, 2.4] : [0, 1.25, 4.4]
            keyPosition = [-3, 4, 3]
            fillPosition = [3, 2, 2]
        case .back:
            position = closeUp ? [0, 1.55, -2.4] : [0, 1.25, -4.4]
            keyPosition = [3, 4, -3]
            fillPosition = [-3, 2, -2]
        case .side:
            position = closeUp ? [2.4, 1.55, 0] : [4.4, 1.25, 0]
            keyPosition = [3, 4, 3]
            fillPosition = [2, 2, -3]
        case .threeQuarter:
            position = closeUp ? [1.5, 1.55, 2.1] : [2.8, 1.25, 3.4]
            keyPosition = [-3, 4, 3]
            fillPosition = [3, 2, 2]
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 36)
        camera.look(at: target, from: position, relativeTo: nil)
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.shadow = nil
        key.look(at: target, from: keyPosition, relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.shadow = nil
        fill.look(at: target, from: fillPosition, relativeTo: nil)
        let frame = try await render(entities: [avatar, key, fill, camera], camera: camera, size: 512)

        var count = 0, left = frame.width, top = frame.height, right = -1, bottom = -1
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let pixel = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 {
                    count += 1
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        XCTAssertGreaterThan(count, 500, "\(label) is empty")
        XCTAssertLessThan(count, frame.width * frame.height * 7 / 10, "\(label) fills the frame")
        XCTAssertGreaterThan(left, 4, "\(label) clipped left")
        XCTAssertGreaterThan(top, 4, "\(label) clipped top")
        XCTAssertLessThan(right, frame.width - 5, "\(label) clipped right")
        if !closeUp { XCTAssertLessThan(bottom, frame.height - 5, "\(label) clipped bottom") }
        let attachment = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = "ReplayXI-Tripo-\(player.team.rawValue)-\(label).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let components = bytes.map { CGFloat($0) / 255 } + [1]
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: components))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(
            await render(entities: [root, camera], camera: camera, size: 256))
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported(
                "Tripo captures require unique row/channel/gamut calibration")
        }
        return calibration
    }

    private func render(entities: [Entity], camera: Entity, size: Int) async throws
        -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Tripo native GPU completion")
        let flag = ReplayTripoCaptureCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Tripo render exceeded ten seconds")
        }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }
}
