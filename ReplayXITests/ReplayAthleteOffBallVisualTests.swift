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

    /// Forced detail comparison, not a simulation of production POV admission.
    /// Actual POV ranks neighbours and switches near/far; low is a parity view.
    func testActualReboundArmsMatchedNearLowFar147() async throws {
        resetProviders()
        defer { resetProviders() }
        try ReplayArmLOD147Probe.prepare()
        let context = try await ReplayArmLOD147Probe.context()
        let calibration = try await calibrate()
        var rows: [[String: Any]] = []
        for playerID in ["arg-13", "arg-19"] {
            let player = try XCTUnwrap(context.scenario.player(id: playerID))
            let input = ReplayArmLOD147Probe.input(context, player: player, time: 0.3)
            try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
            let near = try ReplaySkinnedAthleteProvider.make(for: player, detail: .near)
            let low = try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)
            let far = try ReplayAthleteFactory.make(for: player, lod: .far)
            let avatars = [near.root, low.root, far.root]
            let actor = Entity()
            let origin = SIMD3<Float>(input.presentation.position.x, 0, input.presentation.position.z)
            let heading = simd_quatf(angle: input.presentation.facingDegrees * .pi / 180, axis: [0, 1, 0])
            actor.position = origin; actor.orientation = heading
            for avatar in avatars { actor.addChild(avatar) }
            let scene = Entity(); scene.addChild(actor)
            defer {
                for avatar in avatars { avatar.removeFromParent() }
                actor.removeFromParent()
                for child in Array(scene.children) { child.removeFromParent() }
            }
            ReplayArmLOD147Probe.update(near, player: player, input: input)
            ReplayArmLOD147Probe.update(low, player: player, input: input)
            ReplayArmLOD147Probe.update(far, player: player, input: input)
            try assertDimensionsAndFloor(near); try assertDimensionsAndFloor(low)
            XCTAssertEqual(far.metrics.modelEntities, 7)
            XCTAssertNotNil(far.joints.articulatedFar)
            let arms = try [
                ReplayArmLOD147Probe.arms(near, pose: ReplayArmLOD147Probe.submitted(near), relativeTo: actor),
                ReplayArmLOD147Probe.arms(low, pose: ReplayArmLOD147Probe.submitted(low), relativeTo: actor),
                ReplayArmLOD147Probe.arms(far, relativeTo: actor)
            ]
            let skinTransforms = [near.model.jointTransforms, low.model.jointTransforms]
            let farTransforms = ReplayAthleteJoint.allCases.map { far.joints[$0].transform }
            let actorTransform = actor.transform
            let rootTransforms = avatars.map(\.transform)
            let floor = ModelEntity(mesh: .generateBox(size: [1.8, 0.008, 1.8]),
                materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                           roughness: 1, isMetallic: false)])
            floor.position = origin + [0, -0.006, 0]; scene.addChild(floor)
            let camera = PerspectiveCamera()
            camera.camera = .init(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
            let key = DirectionalLight(); key.light.intensity = 2_200
            key.look(at: origin + [0, 0.9, 0], from: origin + heading.act([3, 4, 3]), relativeTo: nil)
            let fill = DirectionalLight(); fill.light.intensity = 500
            fill.look(at: origin + [0, 0.9, 0], from: origin + heading.act([-3, 2, 2]), relativeTo: nil)
            let views: [(String, SIMD3<Float>)] = [
                ("front", [0, 1.45, 3.8]),
                ("folded-side", [playerID == "arg-13" ? -2.2 : 2.2, 1.45, 3.2])
            ]
            for (view, cameraOffset) in views {
                camera.look(at: origin + [0, 0.95, 0], from: origin + heading.act(cameraOffset), relativeTo: nil)
                let cameraTransform = camera.transform
                for (index, detail) in ["near", "low", "far"].enumerated() {
                    for (candidate, avatar) in avatars.enumerated() { avatar.isEnabled = candidate == index }
                    XCTAssertEqual(avatars.filter(\.isEnabled).count, 1)
                    let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                    XCTAssertGreaterThan(nonBackgroundPixels(frame), 5_000)
                    XCTAssertEqual(camera.transform, cameraTransform)
                    XCTAssertEqual(actor.transform, actorTransform)
                    XCTAssertEqual(avatars.map(\.transform), rootTransforms)
                    XCTAssertEqual(near.model.jointTransforms, skinTransforms[0])
                    XCTAssertEqual(low.model.jointTransforms, skinTransforms[1])
                    XCTAssertEqual(ReplayAthleteJoint.allCases.map { far.joints[$0].transform }, farTransforms)
                    let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                              uniformTypeIdentifier: "public.png")
                    image.name = "ReplayXI-ArmLOD147-\(playerID)-0.300-\(view)-\(detail).png"
                    image.lifetime = .keepAlways; add(image)
                    rows.append(["scenario": context.scenario.id, "player": playerID, "time": input.time,
                        "detail": detail, "view": view, "left": arms[index][0].row, "right": arms[index][1].row,
                        "cameraOffsetActorMetres": ReplayArmLOD147Probe.vector(cameraOffset),
                        "cameraTargetOffsetMetres": [0, 0.95, 0], "cameraFOV": 40,
                        "actorWorldPosition": ReplayArmLOD147Probe.vector(origin),
                        "actorHeadingDegrees": input.presentation.facingDegrees,
                        "ballWorldPosition": ReplayArmLOD147Probe.vector(input.ball.position),
                        "lookWorldPosition": ReplayArmLOD147Probe.vector(input.look),
                        "speedMetresPerSecond": input.locomotion.speedMetresPerSecond,
                        "locomotionState": input.locomotion.state.rawValue,
                        "sameTimeCameraLightingAndActor": true, "visibilityDoesNotChangeSubmittedPose": true,
                        "scope": "Forced admitted LODs, same native demo frame/camera/lights. Low is parity only; actual POV has near/far admission. No natural visible-switch, motion-quality or headset claim."])
                }
            }
            XCTAssertEqual(context.recording.sample(at: input.time).position, input.ball.position)
            XCTAssertEqual(context.recording.sample(at: input.time).velocity, input.ball.velocity)
        }
        XCTAssertEqual(rows.count, 12)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-ArmLOD147-MatchedVisualReceipts.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    /// Native moving evidence only. Pitch/camera remain fixed while the actual
    /// factory actors travel; source-phase labels do not assert ground contact.
    func testActualReboundBootMotionFixedCameraNearLow149() async throws {
        resetProviders()
        PitchSceneFactory.fullSquadSkinsForTesting = false
        defer { resetProviders() }
        try ReplayArmLOD147Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let context = try await ReplayArmLOD147Probe.context()
        defer {
            // Release expired factory cache ownership before asset reset.
            let empty = Entity(), marks = Entity(); marks.name = "marks-root"; empty.addChild(marks)
            updateSupport149(empty, context: context, wearer: "arg-10", time: 0)
            for child in Array(empty.children) { child.removeFromParent() }
        }
        try ReplayAthleteFactory.prewarm(for: context.scenario.players, lods: [.near, .far])
        let calibration = try await calibrate()
        var rows: [[String: Any]] = [], totalBytes = 0
        for playerID in ["arg-13", "arg-19"] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let result = try await captureSupport149(context, playerID: playerID, detail: detail,
                                                         calibration: calibration)
                rows.append(contentsOf: result.rows); totalBytes += result.bytes
            }
        }
        XCTAssertEqual(rows.count, 136)
        XCTAssertLessThanOrEqual(totalBytes, 96 * 1_024 * 1_024)
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let report: [String: Any] = ["scenario": context.scenario.id, "frames": rows,
            "nativeFrames": rows.count, "frameSize": [512, 512], "sampleRateHz": 60,
            "pngBytes": totalBytes, "renderersForSequences": 4, "gridSpacingMetres": 0.1,
            "baselineReceipt": "E05C64BF-174D-4B18-A745-ABF23C5B22E5.json",
            "scope": "Four native frame sequences, not interpolated/generated frames. Explicit Full squad factory admission; constant diagnostic pitch transform and fixed per-actor camera/light shared by near/low. All actor travel and joint poses remain actual native outputs.",
            "labels": "source-phase-on/off in each attachment name and manifest means the frozen source animation support phase, NOT measured force/contact or proof of sliding. The 10 cm grid is a static, non-colliding diagnostic ground reference.",
            "playback": "Sort each sequence by sourceFrame120Hz. 60 fps is real replay time; 30 fps displays the identical frames at half speed. No encoder or synthetic in-between frames added."]
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-OffBallSupport149-MovingVisualManifest.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    private func captureSupport149(_ context: ReplayArmLOD147Probe.Context, playerID: String,
                                   detail: ReplaySkinnedAthleteProvider.Detail,
                                   calibration: ReplayRealityRendererAudit.Calibration) async throws
        -> (rows: [[String: Any]], bytes: Int) {
        let player = try XCTUnwrap(context.scenario.player(id: playerID))
        let wearer = detail == .near ? "arg-23" : "arg-10"
        let detailName = detail == .near ? "near" : "low"
        let sourceFrames = Array(stride(from: 30, through: 96, by: 2))
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        updateSupport149(root, context: context, wearer: wearer, time: 0.25)
        let skin = try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[playerID])
        XCTAssertEqual(skin.detail, detail)
        XCTAssertNil(PitchSceneFactory.skinnedAthletesForTesting(in: root)[wearer])
        let playersRoot = try XCTUnwrap(root.findEntity(named: "players-root"))
        XCTAssertEqual(playersRoot.transform, Transform())
        let actor = try XCTUnwrap(playersRoot.children.first { $0.name == "player-\(playerID)" })
        XCTAssertTrue(skin.root.parent === actor)
        XCTAssertNotNil(try XCTUnwrap(root.findEntity(named: "pitch"))
            .components[ReplayStrategyPitchProvider.Admission.self])
        let oracle = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
        let centrePose = player.presentationPose(at: 0.525)
        let centre = SIMD3<Float>(centrePose.position.x, 0, centrePose.position.z)
        let heading = simd_quatf(angle: centrePose.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let supportSide: Float = playerID == "arg-13" ? 1 : -1
        let camera = PerspectiveCamera()
        let fov: Float = 45
        camera.camera = .init(near: 0.05, far: 30, fieldOfViewInDegrees: fov)
        camera.look(at: centre + [0, 0.9, 0], from: centre + heading.act([supportSide * 4, 1.45, 2]), relativeTo: nil)
        let key = DirectionalLight(); key.light.intensity = 2_200
        key.look(at: centre, from: centre + [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight(); fill.light.intensity = 1_000
        fill.look(at: centre, from: centre + [-3, 3, -3], relativeTo: nil)
        let cameraTransform = camera.transform, lightTransforms = [key.transform, fill.transform]
        let fixedRootTransform = Transform()
        let grid = supportGrid149(centre: centre)
        root.addChild(grid)
        let gridTransform = grid.transform
        let baseline = supportPointBaseline149(playerID: playerID, detail: detail)
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: [root, camera, key, fill])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 512)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var rows: [[String: Any]] = [], bytes = 0, savedJoints: [[Transform]] = [], savedActors: [Transform] = []
        var savedBootPoints: [SIMD3<Float>] = [], previousFrame: ReplayRealityRendererAudit.Frame?
        var changedFrames = 0, baselineChecks = 0
        for sourceFrame in sourceFrames {
            let time = Double(sourceFrame) / 120
            updateSupport149(root, context: context, wearer: wearer, time: time)
            // This is a fixed diagnostic camera, not the wearer's moving POV.
            // Only the presentation root is normalized; no actor is recentered.
            root.transform = fixedRootTransform
            XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root)[playerID] === skin)
            let expected = player.presentationPose(at: time)
            XCTAssertEqual(actor.position, [expected.position.x, 0, expected.position.z])
            XCTAssertEqual(actor.scale, SIMD3<Float>(repeating: 1))
            let input = ReplayArmLOD147Probe.input(context, player: player, time: time)
            ReplayArmLOD147Probe.update(oracle, player: player, input: input)
            XCTAssertTrue(skin.model.jointTransforms == oracle.model.jointTransforms,
                          "Actual factory/native oracle pose: \(playerID)/\(detailName)/\(time)")
            try assertDimensionsAndFloor(skin)
            let nativeBall = context.recording.pose(at: time)
            let ball = try XCTUnwrap(root.findEntity(named: "ball"))
            XCTAssertEqual(ball.position, [nativeBall.position.x, max(nativeBall.height, 0.11), nativeBall.position.z])
            let bootPoint = try supportVertex149(skin, actor: actor, part: 0, vertex: baseline.vertex)
            if let expectedPoint = baseline.points[sourceFrame] {
                XCTAssertEqual(bootPoint, expectedPoint, "Frozen accepted 149 boot point at \(playerID)/\(detailName)/\(time)")
                baselineChecks += 1
            }
            // Conservative full-body volume; not just a centre-in-cone check.
            let halfFOV = tan(fov * .pi / 360) * 0.97
            for height: Float in [0, 2.10] {
                for x: Float in [-0.75, 0.75] {
                    for z: Float in [-0.75, 0.75] {
                        let projected = camera.convert(position: actor.position + [x, height, z], from: nil)
                        XCTAssertLessThan(projected.z, -0.05)
                        XCTAssertLessThan(abs(projected.x), -projected.z * halfFOV, "Body width crop \(playerID)/\(time)")
                        XCTAssertLessThan(abs(projected.y), -projected.z * halfFOV, "Body height crop \(playerID)/\(time)")
                    }
                }
            }
            let allSkins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            let allJoints = allSkins.mapValues { $0.model.jointTransforms }
            let allActors = playersRoot.children.map(\.transform), ballTransform = ball.transform
            let completed = expectation(description: "Boot support149 native \(playerID)/\(detailName)/\(sourceFrame)")
            let flag = OffBallRenderCompletion()
            try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
                flag.finish(); completed.fulfill()
            })
            await fulfillment(of: [completed], timeout: 10)
            guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Boot support frame timed out") }
            let frame = try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
            XCTAssertGreaterThan(nonBackgroundPixels(frame), 20_000)
            XCTAssertEqual(root.transform, fixedRootTransform); XCTAssertEqual(camera.transform, cameraTransform)
            XCTAssertEqual([key.transform, fill.transform], lightTransforms); XCTAssertEqual(grid.transform, gridTransform)
            XCTAssertTrue(playersRoot.children.map(\.transform) == allActors, "Render must not advance actor travel")
            XCTAssertEqual(ball.transform, ballTransform)
            for (id, body) in allSkins {
                XCTAssertTrue(body.model.jointTransforms == allJoints[id], "Render must not advance native pose \(id)")
            }
            XCTAssertEqual(try supportVertex149(skin, actor: actor, part: 0, vertex: baseline.vertex), bootPoint)
            if let previousFrame, differentPixels(previousFrame, frame) > 20 { changedFrames += 1 }
            previousFrame = frame
            let phase = player.gaitPhase(at: time) - (playerID == "arg-13" ? .pi : 0)
            let marker = phase - floor(phase / (2 * .pi)) * 2 * .pi
            let sourceSupport = marker >= 2.30 && marker <= 3.40
            let name = "ReplayXI-Support149-\(playerID)-\(detailName)-f\(String(format: "%03d", sourceFrame))-t\(String(format: "%.3f", time))-source-phase-\(sourceSupport ? "on" : "off").png"
            let png = try ReplayRealityRendererAudit.png(frame, calibration: calibration)
            bytes += png.count
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            savedJoints.append(skin.model.jointTransforms); savedActors.append(actor.transform); savedBootPoints.append(bootPoint)
            rows.append(["attachment": name, "player": playerID, "detail": detailName, "wearerForAdmission": wearer,
                "sourceFrame120Hz": sourceFrame, "time": time, "sourceSupportPhaseActive": sourceSupport,
                "notMeasuredContact": true, "supportFootAnatomical": playerID == "arg-13" ? "right" : "left",
                "actorPosition": ReplayArmLOD147Probe.vector(actor.position), "facingDegrees": expected.facingDegrees,
                "fixedBootVertex": "part0:v\(baseline.vertex)", "bootPoint": ReplayArmLOD147Probe.vector(bootPoint),
                "cameraPosition": ReplayArmLOD147Probe.vector(camera.position), "cameraFOV": fov,
                "cameraTarget": ReplayArmLOD147Probe.vector(centre + [0, 0.9, 0]), "groundGridSpacing": 0.1])
        }
        XCTAssertEqual(baselineChecks, 2)
        XCTAssertGreaterThan(changedFrames, 25, "A moving sequence must not repeat a static frame")
        for (index, sourceFrame) in sourceFrames.enumerated().reversed() {
            updateSupport149(root, context: context, wearer: wearer, time: Double(sourceFrame) / 120)
            root.transform = fixedRootTransform
            XCTAssertTrue(skin.model.jointTransforms == savedJoints[index], "Exact native sequence rewind")
            XCTAssertEqual(actor.transform, savedActors[index])
            XCTAssertEqual(try supportVertex149(skin, actor: actor, part: 0, vertex: baseline.vertex), savedBootPoints[index])
        }
        return (rows, bytes)
    }

    private func updateSupport149(_ root: Entity, context: ReplayArmLOD147Probe.Context,
                                  wearer: String, time: Double) {
        PitchSceneFactory.update(root: root, scenario: context.scenario, time: time, viewMode: .firstPerson,
            perspectiveID: wearer, marks: context.scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: .fullSquad)
    }

    private func supportGrid149(centre: SIMD3<Float>) -> Entity {
        let grid = Entity(); grid.name = "diagnostic-static-10cm-ground-grid"
        grid.position = [round(centre.x * 10) / 10, 0.0015, round(centre.z * 10) / 10]
        let mesh = MeshResource.generateBox(size: [3.6, 0.001, 0.004])
        let material = UnlitMaterial(color: UIColor(white: 0.34, alpha: 1), applyPostProcessToneMap: false)
        for index in -18...18 {
            for axis in 0..<2 {
                let line = ModelEntity(mesh: mesh, materials: [material])
                if axis == 0 { line.position.z = Float(index) * 0.1 }
                else {
                    line.position.x = Float(index) * 0.1
                    line.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                }
                if index.isMultiple(of: 5) { line.scale.z = 2 }
                XCTAssertNil(line.components[CollisionComponent.self])
                grid.addChild(line)
            }
        }
        XCTAssertEqual(grid.children.count, 74)
        return grid
    }

    private func supportVertex149(_ skin: ReplaySkinnedAthleteInstance, actor: Entity,
                                  part partIndex: Int, vertex: Int) throws -> SIMD3<Float> {
        let contents = try XCTUnwrap(skin.model.model).mesh.contents
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let parts = contents.models.flatMap { Array($0.parts) }
        XCTAssertTrue(parts.indices.contains(partIndex))
        let part = parts[partIndex], weights = try XCTUnwrap(parts[partIndex].jointInfluences).influences.elements
        XCTAssertTrue(part.positions.elements.indices.contains(vertex))
        XCTAssertTrue(weights.count.isMultiple(of: part.positions.count))
        let width = weights.count / part.positions.count
        let point = SIMD4(part.positions.elements[vertex], 1)
        let pose = ReplayArmLOD147Probe.submitted(skin)
        let local = weights[(vertex * width)..<((vertex + 1) * width)].filter { $0.weight > 0 }
            .reduce(SIMD4<Float>.zero) { result, influence in
                result + pose.modelSpaceTransforms[influence.jointIndex]
                    * (skeleton.joints[influence.jointIndex].inverseBindPoseMatrix * point) * influence.weight
            }
        var cursor: Entity? = skin.model, matrix = matrix_identity_float4x4, count = 0, foundSkinRoot = false
        while let entity = cursor, entity !== actor {
            guard count < 16 else { throw CocoaError(.fileReadCorruptFile) }
            matrix = entity.transform.matrix * matrix
            foundSkinRoot = foundSkinRoot || entity === skin.root
            cursor = entity.parent; count += 1
        }
        guard cursor === actor, foundSkinRoot, skin.root.parent === actor else { throw CocoaError(.fileReadCorruptFile) }
        let pitch = actor.transform.matrix * matrix * local
        return [pitch.x, pitch.y, pitch.z]
    }

    private func supportPointBaseline149(playerID: String, detail: ReplaySkinnedAthleteProvider.Detail)
        -> (vertex: Int, points: [Int: SIMD3<Float>]) {
        // Frozen accepted numeric receipt, not regenerated from this capture.
        if playerID == "arg-13", detail == .near {
            return (2987, [56: [9.040996551513672, 0.009834503754973412, -16.843204498291016],
                           74: [9.007147789001465, 0.011782187968492508, -16.963958740234375]])
        }
        if playerID == "arg-13" {
            return (1110, [56: [9.037618637084961, 0.012078491970896721, -16.839021682739258],
                           74: [9.00346851348877, 0.012547332793474197, -16.959627151489258]])
        }
        if detail == .near {
            return (2481, [60: [-8.896486282348633, 0.016740329563617706, -16.61403465270996],
                           78: [-9.05081844329834, 0.006000031717121601, -16.765060424804688]])
        }
        return (863, [60: [-8.89340877532959, 0.01773698814213276, -16.609392166137695],
                      78: [-9.04787826538086, 0.005999987944960594, -16.759946823120117]])
    }

    /// Actual first-person squad admission, not the forced single-actor LOD
    /// comparison above. Eye height is a fixed 1.70 m test stand-in for the
    /// wearer's headset; the production root supplies the player's position.
    /// These stills do not establish device FPS or headset comfort.
    func testActualSquadLowSkinsMatchedPOV147() async throws {
        resetProviders()
        ReplayStrategyBallProvider.resetForTesting()
        let priorSquadFlag = PitchSceneFactory.fullSquadSkinsForTesting
        defer {
            PitchSceneFactory.fullSquadSkinsForTesting = priorSquadFlag
            ReplayStrategyBallProvider.resetForTesting()
            resetProviders()
        }
        try ReplayArmLOD147Probe.prepare()
        // Match room admission, not the primitive pitch/ball fallbacks. The
        // pitch keeps its immutable shared cache, as in the strategy tests.
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let context = try await ReplayArmLOD147Probe.context()
        let scenario = context.scenario
        let time = 0.3
        let wearerID = "arg-10"
        let calibration = try await calibrate()
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: context.recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        XCTAssertNotNil(pitch.components[ReplayStrategyPitchProvider.Admission.self])
        XCTAssertNotNil(root.findEntity(named: ReplayStrategyBallProvider.visualRootName))
        let camera = PerspectiveCamera()
        let fov: Float = 90
        camera.camera = .init(near: 0.05, far: 150, fieldOfViewInDegrees: fov)
        let key = DirectionalLight(); key.light.intensity = 2_200
        key.look(at: [0, 0, 0], from: [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight(); fill.light.intensity = 1_600
        fill.look(at: [0, 0, 0], from: [-3, 4, -3], relativeTo: nil)
        let lightTransforms = [key.transform, fill.transform]
        let views: [(name: String, targets: [String])] = [
            ("attacking-group", ["arg-22", "fra-4"]),
            ("midfield-group", ["arg-5", "fra-8"])
        ]
        var rows: [[String: Any]] = []

        func body(_ id: String) throws -> Entity {
            try XCTUnwrap(root.findEntity(named: "player-\(id)"))
        }
        func visibleModels(_ entity: Entity) -> Int {
            guard entity.isEnabledInHierarchy else { return 0 }
            return (entity.components[ModelComponent.self] == nil ? 0 : 1)
                + entity.children.reduce(0) { $0 + visibleModels($1) }
        }

        for view in views {
            var baselineFrame: ReplayRealityRendererAudit.Frame?
            var baselineRoot: Transform?
            var baselineCamera: Transform?
            var baselineBodies: [String: Transform] = [:]
            var baselineBall: Transform?
            var baselineNearIDs: [String] = []
            var baselineNearJoints: [String: [Transform]] = [:]
            for fullSquad in [false, true] {
                PitchSceneFactory.fullSquadSkinsForTesting = fullSquad
                PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .firstPerson,
                    perspectiveID: wearerID, marks: scenario.coachMarks, showsLaneLens: false,
                    isDrawing: false, positionalOriginTransform: nil)
                let wearer = try body(wearerID)
                let eye = wearer.convert(position: [0, 1.70, 0], to: nil)
                XCTAssertEqual(eye.x, 0, accuracy: 0.000_01)
                XCTAssertEqual(eye.y, 1.70, accuracy: 0.000_01)
                XCTAssertEqual(eye.z, 0, accuracy: 0.000_01)
                let targets = try view.targets.map { try body($0).convert(position: [0, 1.05, 0], to: nil) }
                // A world-position midpoint biases towards the farther actor
                // and can crop the nearer one. Bisect their angular directions
                // instead; both actors retain the same actual pitch positions.
                let directions = targets.map { simd_normalize($0 - eye) }
                let directionSum = directions.reduce(SIMD3<Float>.zero, +)
                XCTAssertGreaterThan(simd_length_squared(directionSum), 0.01)
                let gaze = eye + simd_normalize(directionSum) * 10
                camera.look(at: gaze, from: eye, relativeTo: nil)
                XCTAssertEqual(visibleModels(wearer), 0, "The actual POV wearer must remain invisible")
                XCTAssertNil(PitchSceneFactory.skinnedAthletesForTesting(in: root)[wearerID])
                XCTAssertFalse(try XCTUnwrap(wearer.findEntity(named: "interaction-target")).isEnabledInHierarchy)

                let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
                let nearIDs = skins.filter { $0.value.detail == .near }.keys.sorted()
                let lowIDs = skins.filter { $0.value.detail == .lowDetail }.keys.sorted()
                let enabledSkinIDs = skins.filter { $0.value.root.isEnabledInHierarchy }.keys.sorted()
                let farIDs = try scenario.players.compactMap { player -> String? in
                    let far = try XCTUnwrap(body(player.id).children.first { $0.name == "table-marker" })
                    return far.isEnabledInHierarchy ? player.id : nil
                }.sorted()
                XCTAssertEqual(nearIDs.count, PitchSceneFactory.firstPersonDetailedRigLimit)
                XCTAssertEqual(lowIDs.count, fullSquad ? scenario.players.count - 1 - nearIDs.count : 0)
                XCTAssertEqual(enabledSkinIDs.count, fullSquad ? scenario.players.count - 1 : nearIDs.count)
                XCTAssertEqual(farIDs.count, fullSquad ? 0 : scenario.players.count - 1 - nearIDs.count)

                var inView: [[String: Any]] = []
                var inViewTeams: Set<FootballTeam> = []
                let halfFOVTangent = tan(fov * .pi / 360)
                for player in scenario.players where player.id != wearerID {
                    let actor = try body(player.id)
                    let pose = player.presentationPose(at: time)
                    XCTAssertEqual(actor.position, [pose.position.x, 0, pose.position.z])
                    let centre = actor.convert(position: [0, 1, 0], to: nil)
                    let projected = camera.convert(position: centre, from: nil)
                    let distance = simd_distance(centre, eye)
                    guard distance <= 28, projected.z < -0.05,
                          abs(projected.x) < -projected.z * halfFOVTangent,
                          abs(projected.y) < -projected.z * halfFOVTangent else { continue }
                    inViewTeams.insert(player.team)
                    inView.append(["player": player.id, "team": player.team.rawValue,
                        "distanceMetres": distance, "worldCentre": ReplayArmLOD147Probe.vector(centre),
                        "detail": skins[player.id].map { String(describing: $0.detail) } ?? "far"])
                }
                XCTAssertGreaterThanOrEqual(inView.count, 2, "Use a real group, not a single isolated actor")
                XCTAssertEqual(inViewTeams, Set(FootballTeam.allCases), "Both teams must be within this practical POV cone")
                for targetID in view.targets {
                    XCTAssertTrue(inView.contains { $0["player"] as? String == targetID })
                    // A centre-in-cone test alone admitted the cropped first
                    // fixture. Keep a conservative body-width/height envelope
                    // on screen, independent of the two visual LODs' bounds.
                    let origin = try body(targetID).convert(position: .zero, to: nil)
                    let cameraRight = camera.orientation.act(SIMD3<Float>(1, 0, 0))
                    for height in [Float(0), 2.05] {
                        for halfWidth in [Float(-0.75), 0.75] {
                            let corner = origin + [0, height, 0] + cameraRight * halfWidth
                            let projected = camera.convert(position: corner, from: nil)
                            XCTAssertLessThan(projected.z, -0.05)
                            XCTAssertLessThan(abs(projected.x), -projected.z * halfFOVTangent,
                                "The full target body must fit horizontally: \(targetID)")
                            XCTAssertLessThan(abs(projected.y), -projected.z * halfFOVTangent,
                                "The full target body must fit vertically: \(targetID)")
                        }
                    }
                }

                let bodyTransforms = try Dictionary(uniqueKeysWithValues: scenario.players.map {
                    ($0.id, try body($0.id).transform)
                })
                let ball = try XCTUnwrap(root.findEntity(named: "ball"))
                let nativeBall = context.recording.sample(at: time)
                XCTAssertEqual(ball.position, [nativeBall.position.x, max(nativeBall.position.y, 0.11), nativeBall.position.z])
                XCTAssertEqual(ball.orientation.vector, context.recording.orientation(at: time).vector)
                let attachedRecording = try XCTUnwrap(PitchSceneFactory.nativeBallRecordingForTesting(in: root))
                XCTAssertEqual(attachedRecording.samples.map(\.position), context.recording.samples.map(\.position))
                XCTAssertEqual(attachedRecording.samples.map(\.velocity), context.recording.samples.map(\.velocity))
                if fullSquad {
                    XCTAssertEqual(root.transform, baselineRoot)
                    XCTAssertEqual(camera.transform, baselineCamera)
                    XCTAssertEqual(bodyTransforms, baselineBodies)
                    XCTAssertEqual(ball.transform, baselineBall)
                    XCTAssertEqual(nearIDs, baselineNearIDs)
                    for id in nearIDs {
                        XCTAssertEqual(skins[id]?.model.jointTransforms, baselineNearJoints[id])
                    }
                } else {
                    baselineRoot = root.transform; baselineCamera = camera.transform
                    baselineBodies = bodyTransforms; baselineBall = ball.transform; baselineNearIDs = nearIDs
                    baselineNearJoints = skins.filter { $0.value.detail == .near }.mapValues { $0.model.jointTransforms }
                }
                XCTAssertEqual([key.transform, fill.transform], lightTransforms)
                let frame = try await render([root, camera, key, fill], camera: camera, size: 1024)
                XCTAssertGreaterThan(nonBackgroundPixels(frame), 20_000)
                let changed = baselineFrame.map { differentPixels($0, frame) } ?? 0
                if fullSquad { XCTAssertGreaterThan(changed, 20, "Squad admission must make a visible difference") }
                else { baselineFrame = frame }
                let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                    uniformTypeIdentifier: "public.png")
                image.name = "ReplayXI-SquadPOV147-\(wearerID)-0.300-\(view.name)-\(fullSquad ? "full-squad-low" : "current-near-far").png"
                image.lifetime = .keepAlways; add(image)
                rows.append(["scenario": scenario.id, "wearer": wearerID, "time": time, "view": view.name,
                    "fullSquadSkinsForTesting": fullSquad, "nearIDs": nearIDs, "lowIDs": lowIDs,
                    "enabledSkinIDs": enabledSkinIDs, "enabledFarIDs": farIDs,
                    "within28MetresAndCameraCone": inView, "cameraFOV": fov, "frameSize": [1024, 1024],
                    "cameraWorldPosition": ReplayArmLOD147Probe.vector(eye),
                    "cameraWorldTarget": ReplayArmLOD147Probe.vector(gaze),
                    "gazeFraming": "Angular bisector of target directions; 1.5m wide ×2.05m high target envelopes fit",
                    "lightIntensities": [2_200, 1_600],
                    "strategyPitchAndBallAdmitted": true,
                    "pitchRootPosition": ReplayArmLOD147Probe.vector(root.position),
                    "changedPixelsOverTwoChannelLevels": changed,
                    "sameBallPlayerRootsCameraAndLights": true, "wearerVisibleModels": visibleModels(wearer),
                    "scope": "Production first-person update with actual native recording. Fixed 1.70m test eye height at the transformed wearer position; free-look gaze is held identical for each A/B pair. Debug-only squad admission comparison, not headset imagery, FPS or motion-quality proof."])
            }
        }
        XCTAssertEqual(rows.count, 4)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-SquadPOV147-MatchedVisualReceipts.json"
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
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
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
