import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit
import XCTest
@testable import ReplayXI

private final class OffBallRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Close-up A/B stills of the actual admitted models. Each pair changes only
/// allowsOffBallPose. These are synthetic motion fixtures, not captured match
/// animation, new assets, a headset screenshot or an EA FC quality claim.
@MainActor
final class ReplayAthleteOffBallVisualTests: XCTestCase {
    private struct Fixture {
        let name: String
        let frames: [MotionKeyframe]
        let target: SIMD3<Float>
    }

    func testBothTeamsAcrossNearLowAndFarBeforeAndAfter() async throws {
        resetProviders()
        defer {
            resetProviders()
            XCTAssertFalse(ReplaySkinnedAthleteProvider.isPrewarmed)
            XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
            XCTAssertFalse(ReplayArticulatedFarProvider.isPrewarmed)
            XCTAssertFalse(ReplayArticulatedFarKitProvider.isPrewarmed)
            XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
            XCTAssertFalse(ReplayAthleteHeadProvider.isPrewarmed)
            XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        let calibration = try await calibrate()
        let fixtures = [
            Fixture(name: "idle-side-check", frames: frames(before: 0, after: 0), target: [12, 0.11, 3]),
            Fixture(name: "straight-braking", frames: frames(before: -6, after: 2.6), target: [12, 0.11, 3]),
            Fixture(name: "running-glance", frames: frames(before: -3.6, after: 3.6), target: [-12, 0.11, 5])
        ]
        var report: [[String: Any]] = []
        let time = 1.0
        for team in [FootballTeam.home, .away] {
            for detail in ["near", "low", "far"] {
                for fixture in fixtures {
                    let player = PlayerTrack(id: "offball-visual-\(team.rawValue)-4", displayName: "Defender",
                        role: "CB", shirtNumber: 4, team: team, isGoalkeeper: false, keyframes: fixture.frames)
                    try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
                    let presentation = player.presentationPose(at: time)
                    let locomotion = player.locomotion(at: time)
                    if fixture.name == "straight-braking" {
                        XCTAssertGreaterThan(locomotion.speedMetresPerSecond, 2.25)
                        XCTAssertLessThan(locomotion.accelerationMetresPerSecondSquared, -1)
                    }
                    let far = detail == "far" ? try ReplayAthleteFactory.make(for: player, lod: .far) : nil
                    let skin = detail == "far" ? nil : try ReplaySkinnedAthleteProvider.make(
                        for: player, detail: detail == "near" ? .near : .lowDetail)
                    let avatar = try XCTUnwrap(far?.root ?? skin?.root)
                    let actor = Entity()
                    actor.position = [presentation.position.x, 0, presentation.position.z]
                    actor.orientation = simd_quatf(angle: presentation.facingDegrees * .pi / 180, axis: [0, 1, 0])
                    actor.addChild(avatar)
                    defer { avatar.removeFromParent(); actor.removeFromParent() }
                    let scene = Entity()
                    scene.addChild(actor)
                    defer { for child in Array(scene.children) { child.removeFromParent() } }
                    let floor = ModelEntity(mesh: .generateBox(size: [1.4, 0.008, 1.4]),
                        materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                                   roughness: 1, isMetallic: false)])
                    floor.position.y = -0.006
                    scene.addChild(floor)
                    let camera = PerspectiveCamera()
                    camera.camera = .init(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
                    camera.look(at: [0, 0.95, 0], from: [2.2, 1.45, 3.2], relativeTo: nil)
                    let key = DirectionalLight()
                    key.light.intensity = 2_200
                    key.look(at: [0, 0.9, 0], from: [3, 4, 3], relativeTo: nil)
                    let fill = DirectionalLight()
                    fill.light.intensity = 500
                    fill.look(at: [0, 0.9, 0], from: [-3, 2, 2], relativeTo: nil)
                    let actorTransform = actor.transform
                    let avatarTransform = avatar.transform
                    let originalMesh = skin?.model.model?.mesh

                    func update(_ enabled: Bool, interaction: ReplayAthleteInteractionCue? = nil) {
                        if let skin {
                            XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                                lookTarget: fixture.target, ballAction: nil, interaction: interaction,
                                presentationPose: presentation, allowsOffBallPose: enabled))
                        }
                        if let far {
                            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: time,
                                locomotion: locomotion, gaitPhase: player.gaitPhase(at: time),
                                lookTargetWorldPosition: fixture.target, interaction: interaction,
                                presentationPose: presentation, allowsOffBallPose: enabled)
                            ReplayAthleteMotion.apply(pose, to: far.joints)
                        }
                    }

                    var beforeFrame: ReplayRealityRendererAudit.Frame?
                    var baselineSkin: ReplaySkinnedAthleteMotion.Pose?
                    var baselineFarLegs: [Transform] = []
                    var changedPixels = 0
                    let legJoints: [ReplayAthleteJoint] = [.bodyRoot, .hips, .leftHip, .rightHip,
                                                         .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
                    for enabled in [false, true] {
                        update(enabled)
                        XCTAssertEqual(actor.transform, actorTransform)
                        XCTAssertEqual(avatar.transform, avatarTransform)
                        XCTAssertEqual(avatar.scale, .one)
                        if let skin {
                            XCTAssertTrue(skin.model.model?.mesh === originalMesh)
                            XCTAssertEqual(skin.model.jointTransforms.count, 80)
                            try assertDimensionsAndFloor(skin)
                            if let baselineSkin {
                                for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                                    let joint = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                                    for column in 0..<4 {
                                        XCTAssertLessThan(simd_distance(skin.pose.modelSpaceTransforms[joint][column],
                                                                      baselineSkin.modelSpaceTransforms[joint][column]), 0.00001)
                                    }
                                }
                                XCTAssertEqual(skin.pose.scales, baselineSkin.scales)
                            } else { baselineSkin = skin.pose }
                        }
                        if let far {
                            XCTAssertEqual(far.metrics.modelEntities, 7)
                            XCTAssertEqual(far.joints.articulatedFar?.supportPointCount, 426)
                            let legs = legJoints.map { far.joints[$0].transform }
                            if enabled { XCTAssertEqual(legs, baselineFarLegs) } else { baselineFarLegs = legs }
                        }
                        let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                        let occupied = nonBackgroundPixels(frame)
                        XCTAssertGreaterThan(occupied, 5_000, "Close-up body/floor must be visible")
                        XCTAssertLessThan(occupied, 512 * 512 * 3 / 4)
                        if let beforeFrame {
                            changedPixels = differentPixels(beforeFrame, frame)
                            XCTAssertGreaterThan(changedPixels, 20, "The enabled upper-body change should be inspectable")
                        } else { beforeFrame = frame }
                        let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                                  uniformTypeIdentifier: "public.png")
                        image.name = "ReplayXI-OffBall128-\(team.rawValue)-\(detail)-\(fixture.name)-\(enabled ? "after" : "before").png"
                        image.lifetime = .keepAlways
                        add(image)
                    }

                    // Exact contact-core A/B control, not a new collision bake.
                    // The full native football-contact suites remain the source
                    // of the foot/head/palm surface proof for the five studies.
                    let contact = ReplayAthleteInteractionCue(playerID: player.id, kind: .pass,
                        contactTime: time, startTime: time - 0.3, endTime: time + 0.3, kickingLeg: .right,
                        contactBallWorldPosition: [0.25, 0.11, 0.35], outgoingDirectionWorld: [0, 0, 1])
                    update(false, interaction: contact)
                    let contactSkin = skin?.model.jointTransforms
                    let contactFar = far.map { value in ReplayAthleteJoint.allCases.map { value.joints[$0].transform } }
                    update(true, interaction: contact)
                    XCTAssertEqual(skin?.model.jointTransforms, contactSkin)
                    XCTAssertEqual(far.map { value in ReplayAthleteJoint.allCases.map { value.joints[$0].transform } }, contactFar)
                    report.append([
                        "team": team.rawValue, "detail": detail, "fixture": fixture.name, "time": time,
                        "lookTargetMetres": [fixture.target.x, fixture.target.y, fixture.target.z],
                        "speedMetresPerSecond": locomotion.speedMetresPerSecond,
                        "accelerationMetresPerSecondSquared": locomotion.accelerationMetresPerSecondSquared,
                        "changedPixelsOverTwoChannelLevels": changedPixels,
                        "cameraPosition": [2.2, 1.45, 3.2], "cameraTarget": [0, 0.95, 0], "cameraFOV": 40,
                        "frameSize": [512, 512], "sameRootAndScale": true, "sameLegPose": true,
                        "contactCoreToggleIdentical": true,
                        "nearAssetSHA256": ReplaySkinnedAthleteProvider.assetSHA256,
                        "lowAssetSHA256": ReplaySkinnedAthleteProvider.lowAssetSHA256,
                        "scope": "Same licensed assets, exact same input and camera; toggle off-ball upper-body layer only. Synthetic motion fixture, not FIFA/EA FC assets or mocap. No full-match contact, frame-rate, motion-video or headset claim."
                    ])
                }
            }
        }
        XCTAssertEqual(report.count, 18)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-OffBall128-Before-After-Receipts.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    /// Reuse the admitted renderer/calibration for two measured native cases.
    /// The single toggle restores the old relaxed-arm overwrite only.
    func testActualReadyDefendersNearLowBeforeAfter145() async throws {
        resetProviders()
        defer { resetProviders() }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let calibration = try await calibrate()
        var rows: [[String: Any]] = []
        let cases: [(String, String, Double)] = [("city-45-overlap-header", "liv-4", 6.0),
                                                ("city-57-underlap-cutback", "liv-5", 5.9)]
        for (scenarioID, playerID, time) in cases {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == scenarioID })
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            XCTAssertFalse(recording.touches.contains { $0.playerID == playerID })
            let pose = player.presentationPose(at: time), locomotion = player.locomotion(at: time)
            let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
            let ball = recording.sample(at: time)
            let look = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose,
                ball: ball.position, players: scenario.players, poses: poses, contacts: [])
            let heading = simd_quatf(angle: pose.facingDegrees * .pi / 180, axis: [0, 1, 0])
            let origin = SIMD3<Float>(pose.position.x, 0, pose.position.z)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                let actor = Entity()
                actor.position = origin; actor.orientation = heading; actor.addChild(skin.root)
                let scene = Entity(); scene.addChild(actor)
                defer {
                    skin.poseStageObserverForTesting = nil
                    skin.root.removeFromParent(); actor.removeFromParent()
                    for child in Array(scene.children) { child.removeFromParent() }
                }
                let floor = ModelEntity(mesh: .generateBox(size: [1.4, 0.008, 1.4]),
                    materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                               roughness: 1, isMetallic: false)])
                floor.position = origin + [0, -0.006, 0]; scene.addChild(floor)
                let camera = PerspectiveCamera()
                camera.camera = .init(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
                camera.look(at: origin + [0, 0.95, 0],
                            from: origin + heading.act([2.2, 1.45, 3.2]), relativeTo: nil)
                let key = DirectionalLight(); key.light.intensity = 2_200
                key.look(at: origin + [0, 0.9, 0], from: origin + heading.act([3, 4, 3]), relativeTo: nil)
                let fill = DirectionalLight(); fill.light.intensity = 500
                fill.look(at: origin + [0, 0.9, 0], from: origin + heading.act([-3, 2, 2]), relativeTo: nil)
                let actorTransform = actor.transform, skinTransform = skin.root.transform
                let mesh = skin.model.model?.mesh
                var beforeFrame: ReplayRealityRendererAudit.Frame?
                var beforePose: ReplaySkinnedAthleteMotion.Pose?
                var source: ReplaySkinnedAthleteMotion.Pose?, beforeSource: ReplaySkinnedAthleteMotion.Pose?
                skin.poseStageObserverForTesting = { stage, pose in if stage == .source { source = pose } }
                var changed = 0
                for enabled in [false, true] {
                    skin.disablesOffBallReadyArmsForTesting = !enabled
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                        lookTarget: look, ballAction: nil, presentationPose: pose, allowsTrackLocomotionSampling: true))
                    XCTAssertEqual(actor.transform, actorTransform); XCTAssertEqual(skin.root.transform, skinTransform)
                    XCTAssertTrue(skin.model.model?.mesh === mesh)
                    try assertDimensionsAndFloor(skin)
                    if let beforePose {
                        XCTAssertEqual(skin.pose.translations, beforePose.translations)
                        XCTAssertEqual(skin.pose.scales, beforePose.scales)
                        for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                            let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                            XCTAssertEqual(skin.pose.modelSpaceTransforms[index], beforePose.modelSpaceTransforms[index])
                        }
                        XCTAssertEqual(source?.rotations, beforeSource?.rotations)
                        XCTAssertEqual(source?.translations, beforeSource?.translations)
                    } else { beforePose = skin.pose; beforeSource = source }
                    let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                    XCTAssertGreaterThan(nonBackgroundPixels(frame), 5_000)
                    if let beforeFrame {
                        changed = differentPixels(beforeFrame, frame)
                        XCTAssertGreaterThan(changed, 20, "The measured ready-arm restoration must be visible")
                    } else { beforeFrame = frame }
                    let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                              uniformTypeIdentifier: "public.png")
                    image.name = "ReplayXI-ReadyArms145-\(scenarioID)-\(playerID)-\(detail)-\(enabled ? "after" : "before").png"
                    image.lifetime = .keepAlways; add(image)
                }
                XCTAssertEqual(recording.sample(at: time).position, ball.position)
                XCTAssertEqual(recording.sample(at: time).velocity, ball.velocity)
                rows.append(["scenario": scenarioID, "player": playerID, "time": time,
                    "detail": String(describing: detail), "changedPixelsOverTwoChannelLevels": changed,
                    "sourceBallFeetAndPlacementExact": true,
                    "scope": "Same actual demo frame, admitted mesh and camera. Native offscreen A/B, not a headset or match-mocap claim."])
            }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-ReadyArms145-VisualReceipts.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    private func frames(before: Float, after: Float) -> [MotionKeyframe] {
        [.init(time: 0, position: .init(x: 0, z: before), facingDegrees: 0),
         .init(time: 1, position: .zero, facingDegrees: 0),
         .init(time: 2, position: .init(x: 0, z: after), facingDegrees: 0)]
    }

    private func assertDimensionsAndFloor(_ skin: ReplaySkinnedAthleteInstance) throws {
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                    skin.contactSurface.paddingMetres - 0.0001)
        for side in ["left", "right"] {
            for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3,
                                         skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                let posed = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3,
                                          skin.pose.modelSpaceTransforms[b].columns.3)
                XCTAssertEqual(posed, rest, accuracy: 0.0002)
            }
        }
    }

    private func nonBackgroundPixels(_ frame: ReplayRealityRendererAudit.Frame) -> Int {
        stride(from: 0, to: frame.bgra.count, by: 4).reduce(0) { count, index in
            count + (max(frame.bgra[index], frame.bgra[index + 1], frame.bgra[index + 2]) > 8 ? 1 : 0)
        }
    }

    private func differentPixels(_ first: ReplayRealityRendererAudit.Frame,
                                 _ second: ReplayRealityRendererAudit.Frame) -> Int {
        guard first.width == second.width, first.height == second.height else { return 0 }
        return stride(from: 0, to: first.bgra.count, by: 4).reduce(0) { count, index in
            let difference = (0..<3).contains { abs(Int(first.bgra[index + $0]) - Int(second.bgra[index + $0])) > 2 }
            return count + (difference ? 1 : 0)
        }
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(await render([root, camera], camera: camera, size: 256))
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1)
        let calibration = try XCTUnwrap(matches.first)
        let receipt = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-OffBall128-Calibration.json"
        receipt.lifetime = .keepAlways
        add(receipt)
        return calibration
    }

    private func render(_ entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        defer { renderer.entities.removeAll() }
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Off-ball A/B native frame")
        let flag = OffBallRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Off-ball frame timed out") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func resetProviders() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
    }
}
