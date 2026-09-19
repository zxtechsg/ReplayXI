import CoreGraphics
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class Fast137RenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func complete() { lock.withLock { finished = true } }
    var isComplete: Bool { lock.withLock { finished } }
}

/// Native measurements of authored reconstruction motion, not match tracking.
@MainActor
final class ReplayFastDirection137Tests: XCTestCase {
    @MainActor
    private struct Fixture {
        let scenario: ReplayScenario
        let track: PlayerTrack
        let recording: ReplayNativeBallPhysics.Recording
        let cues: [ReplayAthleteInteractionCue]

        func interaction(at time: Double) -> ReplayAthleteInteractionCue? {
            cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
        }
    }

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func fixture(_ id: String, player: String) async throws -> Fixture {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == id })
        let track = try XCTUnwrap(scenario.player(id: player))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let cues = try recording.touches.filter { $0.playerID == player }.map {
            ReplayAthleteInteractionCue(playerID: player,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        return .init(scenario: scenario, track: track, recording: recording, cues: cues)
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, fixture: Fixture, time: Double) -> PlayerPose {
        let track = fixture.track
        let pose = track.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: fixture.scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
        let look = ReplayAthleteTacticalAttention.target(for: track, at: time, pose: pose,
            ball: fixture.recording.sample(at: time).position, players: fixture.scenario.players,
            poses: poses, contacts: fixture.cues)
        XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
            lookTarget: look, ballAction: nil, interaction: fixture.interaction(at: time), presentationPose: pose))
        return pose
    }

    func testActualFastDirectionBaselineSolesBonesFloorAndExactRewind() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        let windows: [(String, String, Double, Double)] = [
            ("final-36-counter-v2", "fra-22", 6.75, 7.35),
            ("final-108-rebound-v2", "arg-10", 1.20, 1.65)
        ]
        for (id, player, start, end) in windows {
            let context = try await fixture(id, player: player)
            let track = context.track
            let times = stride(from: start, through: end + 0.00001, by: 1.0 / 120).map { $0 }
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                var saved: [[Transform]] = []
                var previousFeet: [String: SIMD3<Float>] = [:]
                var nearFloorDistance: Float = 0
                var nearFloorTime: Double = 0
                var maxSoleSpeed: Float = 0
                var maximumJointStep: Float = 0
                var maximumFastYaw: Float = 0
                for time in times {
                    let presented = update(skin, fixture: context, time: time)
                    if let prior = saved.last {
                        for index in prior.indices {
                            maximumJointStep = max(maximumJointStep,
                                angle(prior[index].rotation, skin.model.jointTransforms[index].rotation))
                        }
                    }
                    saved.append(skin.model.jointTransforms)
                    let before = track.presentationPose(at: time - 0.08).position
                    let after = track.presentationPose(at: time + 0.08).position
                    let velocity = SIMD3<Float>((after.x - before.x) / 0.16, 0, (after.z - before.z) / 0.16)
                    let speed = simd_length(velocity)
                    let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                    let localVelocity = heading.inverse.act(velocity)
                    let yaw = atan2(localVelocity.x, localVelocity.z) * 180 / .pi
                    if speed > 4.5 { maximumFastYaw = max(maximumFastYaw, abs(yaw)) }
                    let intent = ReplayAthleteMovementIntent.sample(track: track, at: time,
                        presentationPose: presented, lookTarget: context.recording.sample(at: time).position,
                        interaction: context.interaction(at: time))
                    var row: [String: Any] = ["scenario": id, "player": player, "time": time,
                        "detail": String(describing: detail), "root": [presented.position.x, presented.position.z],
                        "headingDegrees": presented.facingDegrees, "velocity": [velocity.x, velocity.y, velocity.z],
                        "speed": speed, "travelYawDegrees": yaw, "directionalWeight": intent?.directionalWeight ?? 0,
                        "gaitPhase": track.gaitPhase(at: time), "hasProtectedCue": context.interaction(at: time) != nil]
                    for side in ["left", "right"] {
                        let contact = try XCTUnwrap(skin.motion.footContacts[side])
                        let matrix = skin.pose.modelSpaceTransforms[contact.footJointIndex]
                        let p = matrix * SIMD4(contact.solePoint, 1)
                        let local = SIMD3<Float>(p.x, p.y - skin.motion.geometry.restMinY, p.z)
                        let world = heading.act(local * skin.root.scale)
                            + SIMD3<Float>(presented.position.x, 0, presented.position.z)
                        row[side + "SoleWorld"] = [world.x, world.y, world.z]
                        row[side + "SoleLocal"] = [local.x, local.y, local.z]
                        if let previous = previousFeet[side] {
                            let delta = world - previous
                            let soleVelocity = delta * 120
                            row[side + "SoleVelocityWorld"] = [soleVelocity.x, soleVelocity.y, soleVelocity.z]
                            row[side + "RelativeFootVelocityAlongTravel"] = simd_dot(soleVelocity - velocity,
                                speed > 0.001 ? velocity / speed : .zero)
                            // A geometric near-floor candidate, NOT a force
                            // measurement or proof that this boot is planted.
                            let nearFloor = world.y < 0.035 && previous.y < 0.035
                                && abs(soleVelocity.y) < 0.25
                            row[side + "NearFloorCandidate"] = nearFloor
                            if nearFloor {
                                nearFloorDistance += hypot(delta.x, delta.z)
                                nearFloorTime += 1.0 / 120
                                maxSoleSpeed = max(maxSoleSpeed, hypot(soleVelocity.x, soleVelocity.z))
                            }
                        }
                        previousFeet[side] = world
                        XCTAssertTrue(world.x.isFinite && world.y.isFinite && world.z.isFinite)
                        for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                            let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                            let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                            let current = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3, skin.pose.modelSpaceTransforms[b].columns.3)
                            let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                            XCTAssertEqual(current, rest, accuracy: 0.0002)
                        }
                    }
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                        - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                    rows.append(row)
                }
                rows.append(["summary": true, "player": player, "detail": String(describing: detail),
                    "nearFloorCandidateDistance": nearFloorDistance, "nearFloorCandidateSeconds": nearFloorTime,
                    "maxNearFloorSoleSpeed": maxSoleSpeed, "maxJointStepDegrees": maximumJointStep,
                    "maxFastTravelYawDegrees": maximumFastYaw,
                    "meanNearFloorCandidateSpeed": nearFloorTime > 0 ? nearFloorDistance / Float(nearFloorTime) : 0])
                if player == "fra-22" {
                    // Independent baseline fast-yaw145.55°; candidate11.39°.
                    // Guard the directional fix without pretending the source
                    // clip's remaining foot contact quality has been solved.
                    XCTAssertLessThan(maximumFastYaw, 15)
                    XCTAssertLessThan(maximumJointStep, 10.5,
                        "Do not worsen the existing9.812° peak while fixing facing")
                    // Do not apply this bound to protectedarg-10: his existing
                    // 19.307° contact-adjacent transition is an unchanged control.
                }
                for index in times.indices.reversed() {
                    _ = update(skin, fixture: context, time: times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-FastDirection137-Baseline.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureActualFastDirectionAcrossNearAndLow() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let calibration = try await calibrate()
        let cases: [(String, String, [Double])] = [
            ("final-36-counter-v2", "fra-22", [6.85, 7.05, 7.25]),
            ("final-108-rebound-v2", "arg-10", [1.40])
        ]
        for (id, player, times) in cases {
            let context = try await fixture(id, player: player)
            let originPose = context.track.presentationPose(at: times[times.count / 2])
            let origin = SIMD3<Float>(originPose.position.x, 0, originPose.position.z)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
                for time in times {
                    let presented = update(skin, fixture: context, time: time)
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
                    let floor = ModelEntity(mesh: .generateBox(size: [8, 0.008, 8]),
                        materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                                   roughness: 1, isMetallic: false)])
                    floor.position.y = -0.006
                    scene.addChild(floor)
                    let ball = ModelEntity(mesh: .generateSphere(radius: 0.11),
                        materials: [SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)])
                    ball.position = context.recording.sample(at: time).position - origin
                    scene.addChild(ball)
                    let camera = PerspectiveCamera()
                    camera.camera = .init(near: 0.05, far: 80, fieldOfViewInDegrees: 35)
                    // Same world camera throughout each sequence, not a view
                    // aligned to the changing body heading or moving player.
                    camera.look(at: [0, 0.8, 0], from: [4.0, 2.0, -3.2], relativeTo: nil)
                    let key = DirectionalLight()
                    key.light.intensity = 2_200
                    key.look(at: [0, 0.8, 0], from: [3, 4, -3], relativeTo: nil)
                    let fill = DirectionalLight()
                    fill.light.intensity = 500
                    fill.look(at: [0, 0.8, 0], from: [-3, 2, -2], relativeTo: nil)
                    let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                    let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                             uniformTypeIdentifier: "public.png")
                    image.name = "ReplayXI-FastDirection137-\(player)-\(detail)-\(time).png"
                    image.lifetime = .keepAlways
                    add(image)
                }
            }
        }
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi
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
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Fast direction native frame")
        let flag = Fast137RenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.complete(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Fast direction frame timed out") }
        return try withExtendedLifetime((renderer, entities, camera, output)) {
            try ReplayRealityRendererAudit.read(texture)
        }
    }
}
