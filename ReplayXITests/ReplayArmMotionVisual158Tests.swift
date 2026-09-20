import CoreGraphics
import CryptoKit
import Foundation
import RealityKit
import simd
import UIKit
import XCTest
@testable import ReplayXI

private final class ArmRenderCompletion158: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Original native pixels, not synthetic in-between frames. Separate methods
/// allow one LOD/variant per isolated test process during the cleanup audit.
@MainActor
final class ReplayArmMotionVisual158Tests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private typealias Pose = ReplaySkinnedAthleteMotion.Pose
    private let frames = (Array(stride(from: 180, through: 276, by: 2)) + [219]).sorted()
    private final class Stages {
        var source: Pose?
        var phase: Float = 0
        var bodyInfluence: Float = 0
        func clear() { source = nil; phase = 0; bodyInfluence = 0 }
    }
    private struct Context {
        let scenario: ReplayScenario
        let track: PlayerTrack
        let recording: ReplayNativeBallPhysics.Recording
        let cues: [ReplayAthleteInteractionCue]
        func cue(at time: Double) -> ReplayAthleteInteractionCue? {
            cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
        }
    }
    private struct Sample {
        let frame: Int
        let joints: [Transform]
        let source: Pose
        let actor: Transform
        let ball: Transform
        let phase: Float
        let bodyInfluence: Float
        let armWeight: Float
        let suppression: Float
    }

    override func tearDown() {
        // The capture helper has returned, so its root and all local native
        // instances are gone. A fresh cache entry prunes expired weak roots and
        // releases their strong skin dictionaries before provider reset.
        if let scenario = FootballReferenceScenarios.all.first {
            let empty = Entity(), marks = Entity()
            marks.name = "marks-root"; empty.addChild(marks)
            PitchSceneFactory.update(root: empty, scenario: scenario, time: 0,
                viewMode: .touchline, perspectiveID: scenario.defaultPerspectiveID,
                marks: [], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, playerDetail: .fullSquad)
        }
        PitchSceneFactory.fullSquadSkinsForTesting = false
        ReplayArticulatedFarKitProvider.resetForTesting(); ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting(); ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting(); ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testReboundArg10NearBaselineFixedCamera158() async throws {
        try await capture(detail: .near, baseline: true)
    }
    func testReboundArg10NearCandidateFixedCamera158() async throws {
        try await capture(detail: .near, baseline: false)
    }
    func testReboundArg10LowBaselineFixedCamera158() async throws {
        try await capture(detail: .lowDetail, baseline: true)
    }
    func testReboundArg10LowCandidateFixedCamera158() async throws {
        try await capture(detail: .lowDetail, baseline: false)
    }

    private func context() async throws -> Context {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let track = try XCTUnwrap(scenario.player(id: "arg-10"))
        let planned = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: planned)
        XCTAssertEqual(recording.missedTouchCount, 0)
        XCTAssertEqual(recording.touches.count, planned.count)
        let cues = try recording.touches.filter { $0.playerID == track.id }.map {
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        XCTAssertFalse(cues.isEmpty, "ARG10's recorded contact context must not be discarded")
        return .init(scenario: scenario, track: track, recording: recording, cues: cues)
    }

    private func capture(detail: ReplaySkinnedAthleteProvider.Detail, baseline: Bool) async throws {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try ReplayArmLOD147Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm(); try ReplayStrategyBallProvider.prewarm()
        let context = try await context()
        try ReplayAthleteFactory.prewarm(for: context.scenario.players, lods: [.near, .far])
        let calibration = try await calibrate()
        let originalPlayers = context.scenario.players, originalBall = context.scenario.ball
        let nativePositions = context.recording.samples.map(\.position)
        let nativeVelocities = context.recording.samples.map(\.velocity)
        let nativeOrientations = context.recording.samples.map { $0.orientation.vector }
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        // Keep the whole graph intact until the inner renderer scope returns.
        // Do not manually detach children or copy the149 cleanup snapshot.
        // This ownership boundary is NOT a claim to fix the native crash.
        defer { withExtendedLifetime(root) {} }
        let selected = detail == .near ? context.track.id : "arg-23"
        update(root, context: context, selected: selected, time: 1.5)
        let skin = try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[context.track.id])
        XCTAssertEqual(skin.detail, detail)
        XCTAssertNotNil(PitchSceneFactory.armCutTimelinesForTesting(in: root)[context.track.id])
        let actor = try XCTUnwrap(skin.root.parent), ball = try XCTUnwrap(root.findEntity(named: "ball"))
        XCTAssertTrue(actor.isEnabled); XCTAssertTrue(skin.root.isEnabled)
        let oracle = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
        oracle.disablesArmCutSmoothingForTesting = true
        let stages = Stages()
        skin.poseStageObserverForTesting = { stage, pose in if stage == .source { stages.source = pose } }
        skin.authoredPoseObserverForTesting = { _, phase, influence in
            stages.phase = phase; stages.bodyInfluence = influence
        }
        defer { skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil }

        let middle = context.track.presentationPose(at: 1.9)
        let centre = SIMD3<Float>(middle.position.x, 0, middle.position.z)
        let heading = simd_quatf(angle: middle.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let camera = PerspectiveCamera(), fov: Float = 55
        camera.camera = .init(near: 0.05, far: 100, fieldOfViewInDegrees: fov)
        // Source-only framing, shared exactly across variants and LODs. It is
        // chosen once; neither the camera nor any actor is recentered per tick.
        let target = centre + SIMD3<Float>(0, 1.0, 0)
        var cameraFits = false
        for multiplier: Float in [1, 1.2, 1.4, 1.6, 2] {
            camera.look(at: target, from: target + heading.act([5.2, 1.0, 3.3]) * multiplier, relativeTo: nil)
            cameraFits = frames.allSatisfy { frame in
                let position = context.track.presentationPose(at: Double(frame) / 120).position
                return bodyFits(camera, position: [position.x, 0, position.z], fov: fov)
            }
            if cameraFits { break }
        }
        XCTAssertTrue(cameraFits, "The entire moving body must fit without cropping")
        let key = DirectionalLight(), fill = DirectionalLight()
        key.light.intensity = 2_200; key.look(at: centre, from: centre + [3, 4, 3], relativeTo: nil)
        fill.light.intensity = 1_000; fill.look(at: centre, from: centre + [-3, 3, -3], relativeTo: nil)
        let grid = grid(centre: centre); root.addChild(grid)
        let names = ["hips", "leftHip", "leftKnee", "leftAnkle", "leftToe",
                     "rightHip", "rightKnee", "rightAnkle", "rightToe"]
        let legIndices = try names.map { try XCTUnwrap(skin.motion.semanticJointIndices[$0]) }
        let armNames = ["leftShoulder", "leftElbow", "leftWrist", "rightShoulder", "rightElbow", "rightWrist"]
        let armIndices = try armNames.map { try XCTUnwrap(skin.motion.semanticJointIndices[$0]) }
        let result = try await renderSequence(root: root, skin: skin, oracle: oracle, actor: actor, ball: ball,
            context: context, selected: selected, baseline: baseline, stages: stages,
            camera: camera, lights: [key, fill], grid: grid, fov: fov,
            legs: legIndices, arms: armIndices, calibration: calibration)
        XCTAssertEqual(result.rows.count, 50)
        XCTAssertEqual(result.closeRows.count, 2)
        XCTAssertLessThanOrEqual(result.bytes, 24 * 1_024 * 1_024, "Four cases together are bounded to96MiB")
        XCTAssertEqual(context.scenario.players, originalPlayers); XCTAssertEqual(context.scenario.ball, originalBall)
        XCTAssertEqual(context.recording.samples.map(\.position), nativePositions)
        XCTAssertEqual(context.recording.samples.map(\.velocity), nativeVelocities)
        XCTAssertEqual(context.recording.samples.map { $0.orientation.vector }, nativeOrientations)
        let label = detail == .near ? "near" : "low", variant = baseline ? "baseline157" : "candidate158"
        let receipt: [String: Any] = [
            "scenario": context.scenario.id, "player": context.track.id, "detail": label, "variant": variant,
            "frames": result.rows, "closePeakFrames": result.closeRows,
            "nativeFrames": result.rows.count + result.closeRows.count, "sequenceNativeFrames": result.rows.count,
            "pngBytes": result.bytes,
            "frameSize": [512, 512], "regularSampleRateHz": 60, "extraSourceFrame120Hz": 219,
            "fixedCamera": transform(camera.transform), "cameraFOV": fov,
            "calibration": ["gamut": calibration.gamut.rawValue, "topFirst": calibration.rawRowsAreTopFirst,
                            "maximumChannelError": calibration.maximumChannelError],
            "armJointScope": armNames, "exactLegJointScope": names,
            "peakPair": result.peakPair, "changedArmSamples": result.changed,
            "scope": "Actual full-squad factory admission; baseline disables only new arm-cut admission. Same source, body/leg local transforms, routes, native ball, fixed root/camera/lights/grid and exact rewind. Baseline factory pose equals an independent contact-aware native instance at every frame.",
            "playback": "49 original frames at60Hz from1.5 through2.3s. Frame219 at1.825s is an extra diagnostic still; exclude it for uniform60Hz playback. Never interpolate or treat all50 as uniformly timed. Two additional closePeakFrames use a separate fixed camera only for218/219, not the moving sequence.",
            "limits": "Touchline intentionally hides turf; the noncolliding grid is a diagnostic ground reference. These are native body frames, not normal-room/headset/FPS evidence. Cleanup149 remains unresolved; this isolated session is not a fix claim."
        ]
        attach(try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]),
               name: "ReplayXI-ArmMotion158-\(label)-\(variant).json", type: "public.json")
    }

    private func renderSequence(root: Entity, skin: Skin, oracle: Skin, actor: Entity, ball: Entity,
                                context: Context, selected: String, baseline: Bool, stages: Stages,
                                camera: PerspectiveCamera, lights: [DirectionalLight], grid: Entity, fov: Float,
                                legs: [Int], arms: [Int], calibration: ReplayRealityRendererAudit.Calibration)
        async throws -> (rows: [[String: Any]], closeRows: [[String: Any]], bytes: Int, changed: Int, peakPair: [String: Any]) {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: [root, camera] + lights.map { $0 as Entity })
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 512)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let fixedCamera = camera.transform, fixedLights = lights.map(\.transform), fixedGrid = grid.transform
        let sequenceProjection = camera.camera, closeFOV: Float = 45
        let closeMiddle = context.track.presentationPose(at: 437.0 / 240)
        let closeTarget = SIMD3<Float>(closeMiddle.position.x, 1.0, closeMiddle.position.z)
        let closeHeading = simd_quatf(angle: closeMiddle.facingDegrees * .pi / 180, axis: [0, 1, 0])
        camera.camera = .init(near: 0.05, far: 100, fieldOfViewInDegrees: closeFOV)
        var closeFits = false
        for multiplier: Float in [1, 1.1, 1.2, 1.3, 1.4] {
            camera.look(at: closeTarget, from: closeTarget + closeHeading.act([3.2, 0.65, 1.8]) * multiplier, relativeTo: nil)
            closeFits = [218, 219].allSatisfy { frame in
                let position = context.track.presentationPose(at: Double(frame) / 120).position
                return bodyFits(camera, position: [position.x, 0, position.z], fov: closeFOV)
            }
            if closeFits { break }
        }
        XCTAssertTrue(closeFits, "Close peak camera must fit the whole body at both instants")
        let fixedCloseCamera = camera.transform
        camera.transform = fixedCamera; camera.camera = sequenceProjection
        let detail = skin.detail == .near ? "near" : "low", variant = baseline ? "baseline157" : "candidate158"
        var rows: [[String: Any]] = [], closeRows: [[String: Any]] = [], bytes = 0, changed = 0
        var saved: [Sample] = [], baselineSamples: [Sample] = [], candidateSamples: [Sample] = []
        for frame in frames {
            let time = Double(frame) / 120
            // Pair on the same admitted rig. Rendering happens only after the
            // requested variant has been restored; no factory owns an old rig.
            let first = try sample(root: root, skin: skin, actor: actor, ball: ball, stages: stages,
                context: context, selected: selected, frame: frame, baseline: !baseline)
            let second = try sample(root: root, skin: skin, actor: actor, ball: ball, stages: stages,
                context: context, selected: selected, frame: frame, baseline: baseline)
            let control = baseline ? second : first, candidate = baseline ? first : second
            XCTAssertEqual(control.source.rotations, candidate.source.rotations)
            XCTAssertEqual(control.source.translations, candidate.source.translations)
            XCTAssertEqual(control.source.scales, candidate.source.scales)
            XCTAssertEqual(control.actor, candidate.actor); XCTAssertEqual(control.ball, candidate.ball)
            XCTAssertEqual(control.phase, candidate.phase); XCTAssertEqual(control.bodyInfluence, candidate.bodyInfluence)
            for index in legs { XCTAssertEqual(control.joints[index], candidate.joints[index], skin.motion.jointNames[index]) }
            try updateOracle(oracle, context: context, time: time)
            XCTAssertEqual(control.joints, oracle.model.jointTransforms, "Contact-aware baseline factory oracle at\(time)")
            if arms.contains(where: { control.joints[$0] != candidate.joints[$0] }) { changed += 1 }
            if ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time), track: context.track, at: time) >= 1 {
                XCTAssertEqual(control.joints, candidate.joints, "Protected contact must remain exact")
            }
            baselineSamples.append(control); candidateSamples.append(candidate); saved.append(second)
            XCTAssertTrue(bodyFits(camera, position: actor.position, fov: fov))
            let allSkins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            let submitted = allSkins.mapValues { $0.model.jointTransforms }
            let players = try XCTUnwrap(root.findEntity(named: "players-root"))
            let actorTransforms = players.children.map(\.transform)
            try await render(renderer, output: output, name: "Arm158 \(detail)/\(variant)/\(frame)")
            let image = try withExtendedLifetime((renderer, root, camera, output, skin, oracle)) {
                try ReplayRealityRendererAudit.read(texture)
            }
            XCTAssertEqual(camera.transform, fixedCamera); XCTAssertEqual(lights.map(\.transform), fixedLights)
            XCTAssertEqual(grid.transform, fixedGrid); XCTAssertEqual(root.transform, Transform())
            XCTAssertEqual(actor.transform, second.actor); XCTAssertEqual(ball.transform, second.ball)
            XCTAssertEqual(players.children.map(\.transform), actorTransforms)
            for (id, body) in allSkins { XCTAssertEqual(body.model.jointTransforms, submitted[id]) }
            XCTAssertGreaterThan(nonBlackPixels(image), 1_000, "Native capture must not be blank")
            let png = try ReplayRealityRendererAudit.png(image, calibration: calibration); bytes += png.count
            let name = "ReplayXI-Arm158-arg10-\(detail)-\(variant)-f\(frame)-t\(String(format: "%.6f", time)).png"
            attach(png, name: name, type: "public.png")
            let armPoints = try ReplayArmLOD147Probe.arms(skin, pose: skin.pose, relativeTo: actor)
            rows.append(["attachment": name, "sourceFrame120Hz": frame, "time": time,
                "isExtraDiagnosticStill": frame == 219, "actor": transform(second.actor), "ball": transform(second.ball),
                "camera": transform(camera.transform), "armCutWeight": second.armWeight,
                "armCutSuppression": second.suppression, "phaseAlignmentWeight": second.phase,
                "bodyInfluence": second.bodyInfluence, "gaitPhase": context.track.gaitPhase(at: time),
                "contactProtection": ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time), track: context.track, at: time),
                "anatomicalLeftArm": armPoints[0].row, "anatomicalRightArm": armPoints[1].row,
                "armLocalTransforms": arms.map { transform(second.joints[$0]) },
                "submittedPoseSHA256": poseHash(second.joints), "sourcePoseSHA256": sourceHash(second.source),
                "baselineArmCutWeight": control.armWeight, "candidateArmCutWeight": candidate.armWeight])
            if frame == 218 || frame == 219 {
                camera.transform = fixedCloseCamera
                camera.camera = .init(near: 0.05, far: 100, fieldOfViewInDegrees: closeFOV)
                defer { camera.transform = fixedCamera; camera.camera = sequenceProjection }
                XCTAssertTrue(bodyFits(camera, position: actor.position, fov: closeFOV))
                let projectedSpan = try projectedHeadToAnkleSpan(skin, camera: camera, fov: closeFOV)
                XCTAssertGreaterThanOrEqual(projectedSpan, 180,
                    "Close diagnostic requires a useful native skeleton image span; not pixel segmentation")
                try await render(renderer, output: output, name: "Arm158 close \(detail)/\(variant)/\(frame)")
                let closeImage = try withExtendedLifetime((renderer, root, camera, output, skin, oracle)) {
                    try ReplayRealityRendererAudit.read(texture)
                }
                XCTAssertEqual(camera.transform, fixedCloseCamera); XCTAssertEqual(lights.map(\.transform), fixedLights)
                XCTAssertEqual(grid.transform, fixedGrid); XCTAssertEqual(root.transform, Transform())
                XCTAssertEqual(actor.transform, second.actor); XCTAssertEqual(ball.transform, second.ball)
                XCTAssertEqual(players.children.map(\.transform), actorTransforms)
                for (id, body) in allSkins { XCTAssertEqual(body.model.jointTransforms, submitted[id]) }
                XCTAssertGreaterThan(nonBlackPixels(closeImage), 1_000)
                let closePNG = try ReplayRealityRendererAudit.png(closeImage, calibration: calibration)
                bytes += closePNG.count
                let closeName = "ReplayXI-Arm158-arg10-\(detail)-\(variant)-close-f\(frame)-t\(String(format: "%.6f", time)).png"
                attach(closePNG, name: closeName, type: "public.png")
                var row = try XCTUnwrap(rows.last)
                row["attachment"] = closeName; row["camera"] = transform(camera.transform)
                row["cameraFOV"] = closeFOV; row["shot"] = "fixed-close-peak"
                row["projectedHeadToLowestAnkleSpanPixels"] = projectedSpan
                row["spanDefinition"] = "Projected native head and ankle joints; not measured visible silhouette height or an occlusion test"
                closeRows.append(row)
            }
        }
        XCTAssertEqual(camera.transform, fixedCamera)
        XCTAssertGreaterThan(changed, 0, "Report an actual visible-rig A/B, not an inactive opt-out")
        for snapshot in saved.reversed() {
            let rewound = try sample(root: root, skin: skin, actor: actor, ball: ball, stages: stages,
                context: context, selected: selected, frame: snapshot.frame, baseline: baseline)
            XCTAssertEqual(rewound.joints, snapshot.joints); XCTAssertEqual(rewound.actor, snapshot.actor)
            XCTAssertEqual(rewound.ball, snapshot.ball); XCTAssertEqual(rewound.armWeight, snapshot.armWeight)
            XCTAssertEqual(rewound.suppression, snapshot.suppression)
        }
        let before = try XCTUnwrap(frames.firstIndex(of: 218)), after = try XCTUnwrap(frames.firstIndex(of: 219))
        let pair: [String: Any] = ["beforeTime": Double(218) / 120, "afterTime": Double(219) / 120,
            "jointNames": arms.map { skin.motion.jointNames[$0] },
            "baselineDegrees": arms.map { angle(baselineSamples[before].joints[$0].rotation, baselineSamples[after].joints[$0].rotation) },
            "candidateDegrees": arms.map { angle(candidateSamples[before].joints[$0].rotation, candidateSamples[after].joints[$0].rotation) }]
        return (rows, closeRows, bytes, changed, pair)
    }

    private func sample(root: Entity, skin: Skin, actor: Entity, ball: Entity, stages: Stages,
                        context: Context, selected: String, frame: Int, baseline: Bool) throws -> Sample {
        let time = Double(frame) / 120
        skin.disablesArmCutSmoothingForTesting = baseline; stages.clear()
        update(root, context: context, selected: selected, time: time)
        XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root)[context.track.id] === skin)
        let presented = context.track.presentationPose(at: time), native = context.recording.pose(at: time)
        XCTAssertEqual(actor.position, [presented.position.x, 0, presented.position.z])
        XCTAssertEqual(actor.scale, SIMD3<Float>(repeating: 1))
        XCTAssertEqual(ball.position, [native.position.x, max(native.height, 0.11), native.position.z])
        XCTAssertEqual(skin.slowRunWeightForTesting, 0, "Whole-track touch actor keeps its established source")
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                   skin.contactSurface.paddingMetres - 0.0001)
        return .init(frame: frame, joints: skin.model.jointTransforms, source: try XCTUnwrap(stages.source),
            actor: actor.transform, ball: ball.transform, phase: stages.phase, bodyInfluence: stages.bodyInfluence,
            armWeight: skin.armCutWeightForTesting, suppression: skin.armCutSuppressionForTesting)
    }

    private func updateOracle(_ oracle: Skin, context: Context, time: Double) throws {
        let presentation = context.track.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
        let look = ReplayAthleteTacticalAttention.target(for: context.track, at: time, pose: presentation,
            ball: context.recording.sample(at: time).position, players: context.scenario.players, poses: poses, contacts: context.cues)
        XCTAssertTrue(oracle.update(at: time, track: context.track, locomotion: context.track.locomotion(at: time),
            lookTarget: look, ballAction: nil, interaction: context.cue(at: time), presentationPose: presentation,
            allowsTrackLocomotionSampling: true))
    }

    private func update(_ root: Entity, context: Context, selected: String, time: Double) {
        PitchSceneFactory.update(root: root, scenario: context.scenario, time: time, viewMode: .touchline,
            perspectiveID: selected, marks: [], showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: .fullSquad)
        root.transform = Transform() // Fixed pitch frame, not a per-frame actor recenter.
    }

    private func bodyFits(_ camera: PerspectiveCamera, position: SIMD3<Float>, fov: Float) -> Bool {
        let extent = tan(fov * .pi / 360) * 0.94
        for height: Float in [0, 2.1] {
            for x: Float in [-0.8, 0.8] {
                for z: Float in [-0.8, 0.8] {
                    let p = camera.convert(position: position + [x, height, z], from: nil)
                    if p.z >= -0.05 || abs(p.x) >= -p.z * extent || abs(p.y) >= -p.z * extent { return false }
                }
            }
        }
        return true
    }

    private func projectedHeadToAnkleSpan(_ skin: Skin, camera: PerspectiveCamera, fov: Float) throws -> Float {
        let pose = ReplayArmLOD147Probe.submitted(skin)
        let pixels = try ["head", "leftAnkle", "rightAnkle"].map { name -> Float in
            let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
            let joint = pose.modelSpaceTransforms[index].columns.3
            let p = skin.model.convert(position: [joint.x, joint.y, joint.z], to: camera)
            XCTAssertLessThan(p.z, -0.05)
            return 256 * (1 - p.y / (-p.z * tan(fov * .pi / 360)))
        }
        return try XCTUnwrap(pixels.max()) - XCTUnwrap(pixels.min())
    }

    private func grid(centre: SIMD3<Float>) -> Entity {
        let root = Entity(); root.name = "diagnostic-fixed-quarter-metre-grid"
        root.position = [round(centre.x * 4) / 4, 0.0015, round(centre.z * 4) / 4]
        let mesh = MeshResource.generateBox(size: [8, 0.001, 0.006])
        let material = UnlitMaterial(color: UIColor(white: 0.28, alpha: 1), applyPostProcessToneMap: false)
        for index in -16...16 {
            for axis in 0..<2 {
                let line = ModelEntity(mesh: mesh, materials: [material])
                if axis == 0 { line.position.z = Float(index) * 0.25 }
                else { line.position.x = Float(index) * 0.25; line.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) }
                root.addChild(line)
            }
        }
        return root
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity(); defer { withExtendedLifetime(root) {} }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index); root.addChild(swatch)
        }
        let camera = PerspectiveCamera(); camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let frame = try await calibrationFrame(root: root, camera: camera)
        let matches = try ReplayRealityRendererAudit.probe(frame).candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1); return try XCTUnwrap(matches.first)
    }

    private func calibrationFrame(root: Entity, camera: Entity) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer(); renderer.entities.append(contentsOf: [root, camera])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 256)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try await render(renderer, output: output, name: "Arm158 calibration")
        return try withExtendedLifetime((renderer, root, camera, output)) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func configure(_ renderer: RealityRenderer, camera: Entity) {
        renderer.activeCamera = camera; renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    }
    private func render(_ renderer: RealityRenderer, output: RealityRenderer.CameraOutput, name: String) async throws {
        let completed = expectation(description: name), flag = ArmRenderCompletion158()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); completed.fulfill() })
        await fulfillment(of: [completed], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Arm158 render timed out") }
    }
    private func attach(_ data: Data, name: String, type: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func transform(_ value: Transform) -> [String: [Float]] {
        ["position": [value.translation.x, value.translation.y, value.translation.z],
         "rotation": [value.rotation.vector.x, value.rotation.vector.y, value.rotation.vector.z, value.rotation.vector.w],
         "scale": [value.scale.x, value.scale.y, value.scale.z]]
    }
    private func poseHash(_ transforms: [Transform]) -> String {
        let values = transforms.flatMap { t in
            [t.translation.x, t.translation.y, t.translation.z, t.rotation.vector.x, t.rotation.vector.y,
             t.rotation.vector.z, t.rotation.vector.w, t.scale.x, t.scale.y, t.scale.z]
        }
        return values.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
    }
    private func sourceHash(_ pose: Pose) -> String {
        poseHash(pose.rotations.indices.map { Transform(scale: pose.scales[$0], rotation: pose.rotations[$0], translation: pose.translations[$0]) })
    }
    private func angle(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let difference = simd_normalize(lhs.inverse * rhs)
        return 2 * atan2(simd_length(difference.imag), abs(difference.real)) * 180 / .pi
    }
    private func nonBlackPixels(_ frame: ReplayRealityRendererAudit.Frame) -> Int {
        stride(from: 0, to: frame.bgra.count, by: 4).reduce(0) {
            $0 + (max(frame.bgra[$1], frame.bgra[$1 + 1], frame.bgra[$1 + 2]) > 20 ? 1 : 0)
        }
    }
}
