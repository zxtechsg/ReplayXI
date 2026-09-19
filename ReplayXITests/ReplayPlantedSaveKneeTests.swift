import CoreGraphics
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class SaveKneeRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func complete() { lock.withLock { finished = true } }
    var isComplete: Bool { lock.withLock { finished } }
}

/// Authored animation constraints, not recovered match motion. A parry's
/// outgoing ball direction must not bend planted knees behind their boots.
@MainActor
final class ReplayPlantedSaveKneeTests: XCTestCase {
    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func actualSave() async throws -> (PlayerTrack, ReplayAthleteInteractionCue) {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.bake(
            track: scenario.ball, players: scenario.players, plannedTouches: plan)
        XCTAssertEqual(recording.missedTouchCount, 0)
        let touch = try XCTUnwrap(recording.touches.first { $0.kind == .save })
        let player = try XCTUnwrap(scenario.player(id: touch.playerID))
        return (player, .init(playerID: player.id, kind: .save, contactTime: touch.time,
            startTime: touch.time - 0.32, endTime: touch.time + 0.42, kickingLeg: touch.kickingLeg,
            contactBallWorldPosition: touch.position, outgoingDirectionWorld: touch.outgoingVelocity))
    }

    private func prepare() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
    }

    private func point(_ matrix: simd_float4x4) -> SIMD3<Float> {
        [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z]
    }

    private func alignment(_ skin: ReplaySkinnedAthleteInstance, side: String,
                           expectedForward: SIMD3<Float>) throws -> Float {
        let hip = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Hip"])
        let knee = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Knee"])
        let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Ankle"])
        let upper = point(skin.pose.modelSpaceTransforms[knee]) - point(skin.pose.modelSpaceTransforms[hip])
        let axis = simd_normalize(point(skin.pose.modelSpaceTransforms[ankle]) - point(skin.pose.modelSpaceTransforms[hip]))
        let bend = upper - axis * simd_dot(upper, axis)
        let forward = expectedForward - axis * simd_dot(expectedForward, axis)
        return simd_dot(simd_normalize(bend), simd_normalize(forward))
    }

    func testActualReboundSaveKneesFollowSupportBootsAcrossNearAndLow() async throws {
        let (player, cue) = try await actualSave()
        try prepare()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            for offset in [-0.05, 0, 0.06] {
                let time = cue.contactTime + offset
                let interaction = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: player))
                XCTAssertEqual(interaction.influence, 1)
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                    presentationPose: player.presentationPose(at: time)))
                for side in ["left", "right"] {
                    let value = try alignment(skin, side: side,
                        expectedForward: interaction.supportFootOrientation.act([0, 0, 1]))
                    XCTAssertGreaterThan(value, 0.98, "\(detail) \(side): planted knee must bend with the boot, not the rebound")
                    rows.append(["detail": String(describing: detail), "side": side, "time": time,
                                 "kneeToSupportForwardDot": value])
                }
            }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-PlantedSave-KneeAlignment.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testBothTeamSaveTurnsKeepSolesBonesAndDeterministicRewind() throws {
        try prepare()
        for team in FootballTeam.allCases {
            let player = PlayerTrack(id: "save-turn-\(team.rawValue)", displayName: "Keeper", role: "GK",
                shirtNumber: 1, team: team, isGoalkeeper: true, keyframes: [
                    .init(time: 0, position: .init(x: 0, z: -0.2), facingDegrees: -65),
                    .init(time: 1, position: .zero, facingDegrees: 0),
                    .init(time: 2, position: .init(x: 0, z: -0.2), facingDegrees: 65)
                ])
            let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: .save, contactTime: 1,
                startTime: 0.68, endTime: 1.42, kickingLeg: .right,
                contactBallWorldPosition: [0.1, 0.80, 0.4], outgoingDirectionWorld: [-1, 0.3, -0.4])
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                let times = stride(from: 0.68, through: 1.42, by: 1.0 / 120).map { $0 }
                var poses: [[Transform]] = []
                var planted: [String: SIMD3<Float>] = [:]
                for time in times {
                    let presentation = player.presentationPose(at: time)
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                        lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                        presentationPose: presentation))
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                        - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                    for side in ["left", "right"] {
                        for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                            let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                            let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                            let length = simd_distance(point(skin.pose.modelSpaceTransforms[a]), point(skin.pose.modelSpaceTransforms[b]))
                            let rest = simd_distance(point(skin.motion.restPose.modelSpaceTransforms[a]), point(skin.motion.restPose.modelSpaceTransforms[b]))
                            XCTAssertEqual(length, rest, accuracy: 0.0002)
                        }
                        if let interaction = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: player),
                           interaction.influence == 1 {
                            XCTAssertGreaterThan(try alignment(skin, side: side,
                                expectedForward: interaction.supportFootOrientation.act([0, 0, 1])), 0.98)
                            let contact = try XCTUnwrap(skin.motion.footContacts[side])
                            let sole = skin.pose.modelSpaceTransforms[contact.footJointIndex] * SIMD4(contact.solePoint, 1)
                            let heading = simd_quatf(angle: presentation.facingDegrees * .pi / 180, axis: [0, 1, 0])
                            let world = heading.act([sole.x, sole.y - skin.motion.geometry.restMinY, sole.z])
                                + SIMD3<Float>(presentation.position.x, 0, presentation.position.z)
                            if let first = planted[side] {
                                XCTAssertLessThan(hypot(world.x - first.x, world.z - first.z), 0.0002)
                            } else { planted[side] = world }
                        }
                    }
                    poses.append(skin.model.jointTransforms)
                }
                XCTAssertEqual(planted.count, 2)
                for index in times.indices.reversed() {
                    let time = times[index]
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                        lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                        presentationPose: player.presentationPose(at: time)))
                    XCTAssertEqual(skin.model.jointTransforms, poses[index])
                }
            }
        }
    }

    func testCaptureActualReboundSaveKneesAcrossNearAndLow() async throws {
        let (player, cue) = try await actualSave()
        try prepare()
        let calibration = try await calibrate()
        let presentation = player.presentationPose(at: cue.contactTime)
        let heading = simd_quatf(angle: presentation.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let localBall = heading.inverse.act(cue.contactBallWorldPosition
            - SIMD3<Float>(presentation.position.x, 0, presentation.position.z))
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            XCTAssertTrue(skin.update(at: cue.contactTime, track: player,
                locomotion: player.locomotion(at: cue.contactTime), lookTarget: cue.contactBallWorldPosition,
                ballAction: nil, interaction: cue, presentationPose: presentation))
            let scene = Entity()
            scene.addChild(skin.root)
            defer { for child in Array(scene.children) { child.removeFromParent() } }
            let floor = ModelEntity(mesh: .generateBox(size: [1.8, 0.008, 1.8]),
                materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                           roughness: 1, isMetallic: false)])
            floor.position.y = -0.006
            scene.addChild(floor)
            let ball = ModelEntity(mesh: .generateSphere(radius: 0.11),
                                  materials: [SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)])
            ball.position = localBall
            scene.addChild(ball)
            let camera = PerspectiveCamera()
            camera.camera = .init(near: 0.05, far: 20, fieldOfViewInDegrees: 35)
            camera.look(at: [0, 0.72, 0], from: [1.8, 1.25, 3], relativeTo: nil)
            let key = DirectionalLight()
            key.light.intensity = 2_200
            key.look(at: [0, 0.8, 0], from: [3, 4, 3], relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 500
            fill.look(at: [0, 0.8, 0], from: [-3, 2, 2], relativeTo: nil)
            let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
            let capture = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                        uniformTypeIdentifier: "public.png")
            capture.name = "ReplayXI-PlantedSave-\(detail).png"
            capture.lifetime = .keepAlways
            add(capture)
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
        let completion = expectation(description: "Planted save native frame")
        let flag = SaveKneeRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.complete(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Save frame timed out") }
        return try withExtendedLifetime((renderer, entities, camera, output)) {
            try ReplayRealityRendererAudit.read(texture)
        }
    }
}
