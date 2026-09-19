import CoreGraphics
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class Turn136RenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func complete() { lock.withLock { finished = true } }
    var isComplete: Bool { lock.withLock { finished } }
}

/// Measurements of authored off-ball turns, not recovered match footwork.
@MainActor
final class ReplayStationaryTurn136Tests: XCTestCase {
    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testActualSlowTurnSoleMotionAndExactRewindAcrossNearAndLow() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let windows: [(String, String, Double, Double)] = [
            ("city-57-underlap-cutback", "liv-25", 3.30, 3.80),
            ("city-45-overlap-header", "liv-22", 3.95, 4.20)
        ]
        var rows: [[String: Any]] = []
        for (id, playerID, start, end) in windows {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == id })
            let track = try XCTUnwrap(scenario.player(id: playerID))
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            let shots = ReplayFootballShotTimeline(touches: recording.touches, players: scenario.players)
            let cues = try recording.touches.filter { $0.playerID == playerID }.map {
                ReplayAthleteInteractionCue(playerID: playerID,
                    kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)), contactTime: $0.time,
                    startTime: $0.time - 0.32, endTime: $0.time + 0.42, kickingLeg: $0.kickingLeg,
                    contactBallWorldPosition: $0.position, outgoingDirectionWorld: $0.outgoingVelocity)
            }
            let times = stride(from: start, through: end + 0.00001, by: 1.0 / 120).map { $0 }
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                var saved: [[Transform]] = []
                var supportOrigins: [String: SIMD3<Float>] = [:]
                var supportSamples = 0
                var maximumSupportDrift: Float = 0
                var maximumLift: Float = 0
                var maximumJointStep: Float = 0
                func update(_ time: Double) {
                    let pose = track.presentationPose(at: time)
                    let ball = recording.sample(at: time).position
                    let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
                    let look = ReplayAthleteTacticalAttention.target(for: track, at: time, pose: pose,
                        ball: ball, players: scenario.players, poses: poses, contacts: cues)
                    let readiness = ReplayGoalkeeperReadiness.sample(track: track, at: time,
                        presentationPose: pose, ballPosition: ball,
                        shot: shots.latestOpposingShot(for: track, at: time))
                    XCTAssertFalse(cues.contains { ReplayAthleteMovementIntent.includesPreparation($0, at: time) },
                        "This audit must remain outside protected ball-contact poses")
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: look, ballAction: nil, presentationPose: pose, goalkeeperReadiness: readiness))
                }
                for time in times {
                    update(time)
                    if let prior = saved.last {
                        for index in prior.indices {
                            maximumJointStep = max(maximumJointStep,
                                angle(prior[index].rotation, skin.model.jointTransforms[index].rotation))
                        }
                    }
                    saved.append(skin.model.jointTransforms)
                    let presented = track.presentationPose(at: time)
                    let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                    let turning = ReplaySkinnedAthleteTurnInPlace.sample(track: track, at: time,
                        presentationPose: presented, locomotion: track.locomotion(at: time), interaction: nil,
                        actionInfluence: 0, enabled: true)
                    var row: [String: Any] = ["scenario": id, "player": playerID,
                        "detail": String(describing: detail), "time": time,
                        "root": [presented.position.x, presented.position.z],
                        "headingDegrees": presented.facingDegrees, "gaitPhase": track.gaitPhase(at: time),
                        "turnWeight": turning?.weight ?? 0]
                    var lowestSole = Float.infinity
                    for side in ["left", "right"] {
                        let contact = try XCTUnwrap(skin.motion.footContacts[side])
                        let matrix = skin.pose.modelSpaceTransforms[contact.footJointIndex]
                        let point = matrix * SIMD4(contact.solePoint, 1)
                        let local = SIMD3<Float>(point.x, point.y - skin.motion.geometry.restMinY, point.z)
                        let world = heading.act(local * skin.root.scale)
                            + SIMD3<Float>(presented.position.x, 0, presented.position.z)
                        let forward = heading.act(simd_quatf(matrix).act([0, 0, 1]))
                        XCTAssertTrue(world.x.isFinite && world.y.isFinite && world.z.isFinite)
                        row[side + "SoleWorld"] = [world.x, world.y, world.z]
                        row[side + "SoleLocal"] = [local.x, local.y, local.z]
                        row[side + "ForwardWorld"] = [forward.x, forward.y, forward.z]
                        maximumLift = max(maximumLift, world.y)
                        lowestSole = min(lowestSole, world.y)
                        if let turning, turning.weight > 0.999, turning.foot(left: side == "left").isSupport {
                            if let first = supportOrigins[side] {
                                maximumSupportDrift = max(maximumSupportDrift, hypot(world.x - first.x, world.z - first.z))
                                supportSamples += 1
                            } else { supportOrigins[side] = world }
                        } else { supportOrigins.removeValue(forKey: side) }
                        if let turning, turning.weight > 0.999 {
                            let knee = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Knee"])
                            let sign: Float = contact.restSoleWorld.x < 0 ? -1 : 1
                            XCTAssertGreaterThan(skin.pose.modelSpaceTransforms[knee].columns.3.x * sign, 0.015,
                                "Do not converge the knees across the player's midline during a turn")
                        }
                    }
                    XCTAssertLessThan(lowestSole, 0.025, "Keep a support boot: do not hide sliding by floating both feet")
                    try assertBones(skin)
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                        - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                    rows.append(row)
                }
                XCTAssertLessThan(maximumJointStep, 8, "No abrupt limb change at120Hz")
                if playerID == "liv-25" {
                    // Baseline: both planted soles slid >19cm in this window,
                    // with <0.012mm vertical change. Support must now stay put
                    // while the other boot visibly lifts and repositions.
                    XCTAssertGreaterThan(supportSamples, 40)
                    XCTAssertLessThan(maximumSupportDrift, 0.002)
                    XCTAssertGreaterThan(maximumLift, 0.05)
                }
                rows.append(["summary": true, "player": playerID, "detail": String(describing: detail),
                    "maxSupportDrift": maximumSupportDrift, "supportSamples": supportSamples,
                    "maxSoleHeight": maximumLift, "maxJointStepDegrees": maximumJointStep])
                for index in times.indices.reversed() {
                    update(times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
            }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-StationaryTurn136-Soles.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testPhaseWrapAndReversalKeepAlternatingSupportContinuous() {
        for left in [true, false] {
            for boundary: Float in [-360, -306, -270, -216, -180, -126, -90, -36, 0, 54, 90, 144, 180, 234, 360] {
                let before = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: boundary - 0.001, weight: 1).foot(left: left)
                let after = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: boundary + 0.001, weight: 1).foot(left: left)
                XCTAssertEqual(before.yaw, after.yaw, accuracy: 0.0002)
                XCTAssertEqual(before.lift, after.lift, accuracy: 0.00002)
            }
            let a = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: -180, weight: 1).foot(left: left)
            let b = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: 180, weight: 1).foot(left: left)
            XCTAssertEqual(a.yaw, b.yaw)
            XCTAssertEqual(a.lift, b.lift)
        }
        for degrees in stride(from: Float(-360), through: 360, by: 0.25) {
            let step = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: degrees, weight: 1)
            let a = step.foot(left: true), b = step.foot(left: false)
            XCTAssertTrue(a.isSupport || b.isSupport)
            XCTAssertLessThanOrEqual(min(a.lift, b.lift), 0.000001)
            // This explicit heading-based expected value is independent of
            // playback order. A reversed direction must not change the pose.
            let reverse = ReplaySkinnedAthleteTurnInPlace.Sample(headingDegrees: degrees + 360, weight: 1)
            XCTAssertEqual(a.yaw, reverse.foot(left: true).yaw, accuracy: 0.00001)
        }
    }

    func testBothTeamsTurnReversalPreservesBonesFloorParityAndExactRewind() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var metrics: [[String: Any]] = []
        for team in FootballTeam.allCases {
          for offset: Float in [0, 180, 360] {
            let track = stationaryTurn(team: team, offset: offset)
            let near = try ReplaySkinnedAthleteProvider.make(for: track)
            let low = try ReplaySkinnedAthleteProvider.make(for: track, detail: .lowDetail)
            // Covers turn start/stop and reversal, ±180 and360 root headings.
            let times = stride(from: -0.35, through: 4.35, by: 1.0 / 120).map { $0 }
            var saved: [[[Transform]]] = [[], []]
            var largestSteps: [Float] = [0, 0]
            var largestTimes: [Double] = [0, 0]
            for time in times {
                var soles: [[SIMD3<Float>]] = []
                for (index, skin) in [near, low].enumerated() {
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: nil, ballAction: nil, presentationPose: track.presentationPose(at: time)))
                    try assertBones(skin)
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                        - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                    let feet = try ["left", "right"].map { try sole(skin, side: $0) }
                    XCTAssertLessThan(min(feet[0].y, feet[1].y), 0.025)
                    soles.append(feet)
                    if let prior = saved[index].last {
                        for joint in prior.indices {
                            let step = angle(prior[joint].rotation, skin.model.jointTransforms[joint].rotation)
                            if step > largestSteps[index] {
                                largestSteps[index] = step
                                largestTimes[index] = time
                            }
                            XCTAssertLessThan(step, 8,
                                "\(team) \(skin.detail), joint\(joint), time\(time)")
                        }
                    }
                    saved[index].append(skin.model.jointTransforms)
                }
                for foot in 0..<2 {
                    XCTAssertEqual(soles[0][foot].x, soles[1][foot].x, accuracy: 0.0002)
                    XCTAssertEqual(soles[0][foot].z, soles[1][foot].z, accuracy: 0.0002)
                    XCTAssertEqual(soles[0][foot].y, soles[1][foot].y, accuracy: 0.003)
                }
            }
            for index in times.indices.reversed() {
                for (detail, skin) in [near, low].enumerated() {
                    let time = times[index]
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: nil, ballAction: nil, presentationPose: track.presentationPose(at: time)))
                    XCTAssertEqual(skin.model.jointTransforms, saved[detail][index])
                }
            }
            for index in 0..<2 {
                metrics.append(["team": team.rawValue, "headingOffset": offset,
                    "detail": index == 0 ? "near" : "lowDetail",
                    "maxJointStepDegrees": largestSteps[index], "time": largestTimes[index]])
            }
          }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-StationaryTurn136-Reversals.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testTouchProtectionAndStationaryTeachingPoseRemainUnchanged() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let track = stationaryTurn(team: .home)
        let cue = ReplayAthleteInteractionCue(playerID: track.id, kind: .pass, contactTime: 1,
            startTime: 0.68, endTime: 1.42, kickingLeg: .right,
            contactBallWorldPosition: [0.18, 0.11, 0.3], outgoingDirectionWorld: [1, 0, 1])
        func sample(_ time: Double, influence: Float = 0, enabled: Bool = true) -> ReplaySkinnedAthleteTurnInPlace.Sample? {
            ReplaySkinnedAthleteTurnInPlace.sample(track: track, at: time,
                presentationPose: track.presentationPose(at: time), locomotion: track.locomotion(at: time),
                interaction: cue, actionInfluence: influence, enabled: enabled)
        }
        for time in [0.68, 0.75, 1, 1.3, 1.42] { XCTAssertNil(sample(time)) }
        XCTAssertNil(sample(0.4, influence: 0.05))
        XCTAssertNil(sample(0.4, enabled: false))
        for boundary in [0.56, 0.68, 1.42, 1.54] {
            XCTAssertEqual(sample(boundary - 0.0001)?.weight ?? 0,
                           sample(boundary + 0.0001)?.weight ?? 0, accuracy: 0.0001)
        }
        let skin = try ReplaySkinnedAthleteProvider.make(for: track)
        for time in [0.68, 1.0, 1.42] {
            XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                lookTarget: nil, ballAction: nil, interaction: cue, presentationPose: track.presentationPose(at: time)))
            let normal = skin.model.jointTransforms
            XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                lookTarget: nil, ballAction: nil, interaction: cue, presentationPose: track.presentationPose(at: time),
                allowsOffBallPose: false))
            XCTAssertEqual(skin.model.jointTransforms, normal)
        }
        XCTAssertTrue(skin.update(at: 0.4, track: track, locomotion: track.locomotion(at: 0.4),
            lookTarget: nil, ballAction: nil, stationaryPose: track.presentationPose(at: 0.4),
            presentationPose: track.presentationPose(at: 0.4)))
        let station = skin.model.jointTransforms
        XCTAssertTrue(skin.update(at: 0.4, track: track, locomotion: track.locomotion(at: 0.4),
            lookTarget: nil, ballAction: nil, stationaryPose: track.presentationPose(at: 0.4),
            presentationPose: track.presentationPose(at: 0.4), allowsOffBallPose: false))
        XCTAssertEqual(station, skin.model.jointTransforms)
    }

    private func stationaryTurn(team: FootballTeam, offset: Float = 0) -> PlayerTrack {
        PlayerTrack(id: "turn136-\(team.rawValue)", displayName: "Turn", role: "CB", shirtNumber: 4,
            team: team, isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .zero, facingDegrees: -110 + offset),
                .init(time: 1, position: .zero, facingDegrees: -20 + offset),
                .init(time: 2, position: .zero, facingDegrees: 70 + offset),
                .init(time: 3, position: .zero, facingDegrees: -20 + offset),
                .init(time: 4, position: .zero, facingDegrees: -110 + offset)
            ])
    }

    private func sole(_ skin: ReplaySkinnedAthleteInstance, side: String) throws -> SIMD3<Float> {
        let contact = try XCTUnwrap(skin.motion.footContacts[side])
        let p = skin.pose.modelSpaceTransforms[contact.footJointIndex] * SIMD4(contact.solePoint, 1)
        return [p.x, p.y - skin.motion.geometry.restMinY, p.z]
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi
    }

    private func assertBones(_ skin: ReplaySkinnedAthleteInstance) throws {
        for side in ["left", "right"] {
            for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                XCTAssertEqual(simd_distance(skin.pose.modelSpaceTransforms[a].columns.3, skin.pose.modelSpaceTransforms[b].columns.3),
                    simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3),
                    accuracy: 0.0002)
            }
        }
    }

    func testCaptureActualStationaryTurnAcrossNearAndLow() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "city-57-underlap-cutback" })
        let track = try XCTUnwrap(scenario.player(id: "liv-25"))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let shots = ReplayFootballShotTimeline(touches: recording.touches, players: scenario.players)
        let originPose = track.presentationPose(at: 3.30)
        let origin = SIMD3<Float>(originPose.position.x, 0, originPose.position.z)
        let calibration = try await calibrate()
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            for time in [3.35, 3.60, 3.80] {
                let presented = track.presentationPose(at: time)
                let ballPosition = recording.sample(at: time).position
                let readiness = ReplayGoalkeeperReadiness.sample(track: track, at: time,
                    presentationPose: presented, ballPosition: ballPosition,
                    shot: shots.latestOpposingShot(for: track, at: time))
                XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                    lookTarget: ballPosition, ballAction: nil, presentationPose: presented,
                    goalkeeperReadiness: readiness))
                let scene = Entity()
                let actor = Entity()
                actor.position = SIMD3<Float>(presented.position.x, 0, presented.position.z) - origin
                actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                actor.addChild(skin.root)
                scene.addChild(actor)
                defer {
                    skin.root.removeFromParent()
                    for child in Array(scene.children) { child.removeFromParent() }
                }
                let floor = ModelEntity(mesh: .generateBox(size: [4, 0.008, 4]),
                    materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                               roughness: 1, isMetallic: false)])
                floor.position.y = -0.006
                scene.addChild(floor)
                let ball = ModelEntity(mesh: .generateSphere(radius: 0.11),
                    materials: [SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)])
                ball.position = ballPosition - origin
                scene.addChild(ball)
                let camera = PerspectiveCamera()
                camera.camera = .init(near: 0.05, far: 80, fieldOfViewInDegrees: 35)
                // Fixed WORLD view across every frame, not re-centred on heading.
                camera.look(at: [0, 0.78, 0], from: [-1.8, 1.25, -3], relativeTo: nil)
                let key = DirectionalLight()
                key.light.intensity = 2_200
                key.look(at: [0, 0.8, 0], from: [-3, 4, -3], relativeTo: nil)
                let fill = DirectionalLight()
                fill.light.intensity = 500
                fill.look(at: [0, 0.8, 0], from: [3, 2, -2], relativeTo: nil)
                let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                let capture = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                            uniformTypeIdentifier: "public.png")
                capture.name = "ReplayXI-StationaryTurn136-\(detail)-\(time).png"
                capture.lifetime = .keepAlways
                add(capture)
            }
        }
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for index in ReplayRealityRendererAudit.swatches.indices {
            let swatch = ReplayRealityRendererAudit.swatches[index]
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: swatch.map { CGFloat($0) / 255 } + [1]))
            let tile = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            tile.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(tile)
        }
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(await render([root, camera], camera: camera, size: 256))
        let candidates = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(candidates.count, 1)
        return try XCTUnwrap(candidates.first)
    }

    private func render(_ entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        defer {
            renderer.activeCamera = nil
            renderer.entities.removeAll()
        }
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Stationary turn native frame")
        let flag = Turn136RenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.complete(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Turn frame timed out") }
        return try withExtendedLifetime((renderer, entities, camera, output)) {
            try ReplayRealityRendererAudit.read(texture)
        }
    }
}
