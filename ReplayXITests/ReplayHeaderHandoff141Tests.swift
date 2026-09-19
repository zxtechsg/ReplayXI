import CryptoKit
import CoreGraphics
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class Header141RenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

/// Diagnostic baseline for an authored header hand-off, not recovered match
/// biomechanics. No animation, clock, contact or ball behavior is changed here.
@MainActor
final class ReplayHeaderHandoff141Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage
    // Independent native receipts captured before the header correction.
    private let expected: [String: (positive: String, support: String)] = [
        "near": ("961628c9bac18421b3c09ef3675b153480f0c699f2a75d58598622e1e124fc51",
                 "e6d7695be8bef18031b9bfc8689a36e7f7b35095f840c90bde057f3fb2ad0879"),
        "lowDetail": ("4df5a0efb371ceaf14ba163003b0d031d71d0342c717d1301797d381cad23966",
                      "1485071ba66e237cdddf8e61d29699addd70d2eaf5f87e2ed3915dec50d38283")
    ]
    private let expectedSource = "2b91a57a67ea88857f282dde641c56f648010369f344e9c29c180c0630693b7b"
    private let expectedBall = "36d2f2301e792903ba4c9fe61161210ef4e3669d1acc88309fb1fea87cf4cbe0"

    private final class Capture {
        var stages: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
        var retargetInfluence: Float = 0
        func reset() { stages.removeAll(keepingCapacity: true); retargetInfluence = 0 }
    }

    private struct Context {
        let scenario: ReplayScenario
        let track: PlayerTrack
        let recording: ReplayNativeBallPhysics.Recording
        let cues: [ReplayAthleteInteractionCue]
        let header: ReplayAthleteInteractionCue

        func cue(at time: Double) -> ReplayAthleteInteractionCue? {
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

    private func context() async throws -> Context {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        let track = try XCTUnwrap(scenario.player(id: "fra-10"))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let cues = try recording.touches.filter { $0.playerID == track.id }.map {
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        let header = try XCTUnwrap(cues.first { $0.kind == .header })
        XCTAssertEqual(header.startTime, 4.271666666666667, accuracy: 0.000001)
        XCTAssertEqual(header.endTime, 5.011666666666667, accuracy: 0.000001)
        return .init(scenario: scenario, track: track, recording: recording, cues: cues, header: header)
    }

    private func observe(_ skin: ReplaySkinnedAthleteInstance, into capture: Capture) {
        skin.poseStageObserverForTesting = { stage, pose in capture.stages[stage] = pose }
        skin.authoredPoseObserverForTesting = { _, _, influence in capture.retargetInfluence = influence }
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, context: Context, time: Double) {
        let pose = context.track.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let target = ReplayAthleteTacticalAttention.target(for: context.track, at: time, pose: pose,
            ball: context.recording.sample(at: time).position, players: context.scenario.players,
            poses: poses, contacts: context.cues)
        XCTAssertTrue(skin.update(at: time, track: context.track, locomotion: context.track.locomotion(at: time),
            lookTarget: target, ballAction: nil, interaction: context.cue(at: time), presentationPose: pose,
            allowsTrackLocomotionSampling: true))
    }

    private func metadata(_ context: Context, time: Double) -> [String: Any] {
        let cue = context.cue(at: time)
        let action = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: context.track,
            presentationPose: context.track.presentationPose(at: time))
        let locomotion = context.track.locomotion(at: time)
        return ["time": time, "cuePresent": cue != nil, "samplePresent": action != nil,
            "headerSamplePresent": action?.kind == .header, "interactionInfluence": action?.influence ?? 0,
            "contactProtection": ReplayAthleteMovementIntent.contactProtection(for: cue, track: context.track, at: time),
            "rawCutInfluence": ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil),
            "speed": locomotion.speedMetresPerSecond, "turnRate": locomotion.turnRateDegreesPerSecond,
            "cueStart": context.header.startTime, "cueEnd": context.header.endTime,
            "contactTime": context.header.contactTime]
    }

    private func watchedJoints(_ skin: ReplaySkinnedAthleteInstance) throws -> [Int] {
        try ["hips", "chest", "neck", "head", "leftShoulder", "leftElbow", "leftWrist",
             "rightShoulder", "rightElbow", "rightWrist"].map { try XCTUnwrap(skin.motion.semanticJointIndices[$0]) }
    }

    func testActualHeaderEntryAndExitNativeStagesNearLowAndExactRewind() async throws {
        let context = try await context()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let control = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            control.disablesHeaderHandoffForTesting = true
            let capture = Capture(); observe(skin, into: capture)
            let controlCapture = Capture(); observe(control, into: controlCapture)
            defer {
                for actor in [skin, control] { actor.poseStageObserverForTesting = nil; actor.authoredPoseObserverForTesting = nil }
            }
            let watched = try watchedJoints(skin)
            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            for (edge, boundary) in [("entry", context.header.startTime), ("exit", context.header.endTime)] {
                // Global120Hz matches the original measured 5.008333→5.016667
                // step, rather than moving the sampling grid to hide the edge.
                let first = Int(floor((boundary - 0.16) * 120)), last = Int(ceil((boundary + 0.16) * 120))
                let times = (first...last).map { Double($0) / 120 }
                var previous: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
                var previousControl: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
                var saved: [[Transform]] = [], savedStages: [[Stage: [SIMD4<Float>]]] = []
                var maximumChest: Float = 0, controlMaximumChest: Float = 0
                var maximumJoint: Float = 0, controlMaximumJoint: Float = 0
                for (frame, time) in times.enumerated() {
                    capture.reset(); update(skin, context: context, time: time)
                    controlCapture.reset(); update(control, context: context, time: time)
                    XCTAssertEqual(Set(capture.stages.keys), Set(Stage.allCases))
                    var preceding: ReplaySkinnedAthleteMotion.Pose?
                    var stageSaved: [Stage: [SIMD4<Float>]] = [:]
                    for stage in Stage.allCases {
                        var pose = try XCTUnwrap(capture.stages[stage])
                        let controlPose = try XCTUnwrap(controlCapture.stages[stage])
                        if stage == .source {
                            XCTAssertEqual(pose.rotations, controlPose.rotations)
                            XCTAssertEqual(pose.translations, controlPose.translations)
                        }
                        skin.motion.rebuildModelSpaceTransforms(in: &pose)
                        var row = metadata(context, time: time)
                        row["edge"] = edge; row["detail"] = String(describing: detail); row["stage"] = stage.rawValue
                        row["retargetInfluence"] = capture.retargetInfluence
                        row["chestJoint"] = chest
                        row["jointIndices"] = watched
                        row["jointNames"] = watched.map { skin.motion.joints[$0].name }
                        row["localRotations"] = watched.map { vector(pose.rotations[$0].vector) }
                        row["stageAddedDegrees"] = watched.map { index in
                            preceding.map { angle($0.rotations[index], pose.rotations[index]) } ?? 0
                        }
                        if let prior = previous[stage] {
                            let deltas = pose.rotations.indices.map { angle(prior.rotations[$0], pose.rotations[$0]) }
                            let peak = try XCTUnwrap(deltas.indices.max(by: { deltas[$0] < deltas[$1] }))
                            row["previousTime"] = times[frame - 1]
                            row["watchedJointStepDegrees"] = watched.map { deltas[$0] }
                            row["chestStepDegrees"] = deltas[chest]
                            row["maximumJointStepDegrees"] = deltas[peak]
                            row["maximumJoint"] = peak; row["maximumJointName"] = skin.motion.joints[peak].name
                            let old = try XCTUnwrap(previousControl[stage])
                            let controlDeltas = controlPose.rotations.indices.map { angle(old.rotations[$0], controlPose.rotations[$0]) }
                            row["controlChestStepDegrees"] = controlDeltas[chest]
                            row["controlMaximumJointStepDegrees"] = controlDeltas.max()!
                            row["controlWatchedJointStepDegrees"] = watched.map { controlDeltas[$0] }
                            if stage == .finalFloor {
                                maximumChest = max(maximumChest, deltas[chest])
                                controlMaximumChest = max(controlMaximumChest, controlDeltas[chest])
                                maximumJoint = max(maximumJoint, deltas.max()!)
                                controlMaximumJoint = max(controlMaximumJoint, controlDeltas.max()!)
                            }
                        }
                        XCTAssertTrue(pose.rotations.allSatisfy { $0.vector.x.isFinite && $0.vector.y.isFinite
                            && $0.vector.z.isFinite && $0.vector.w.isFinite })
                        if stage == .finalFloor, let preceding {
                            XCTAssertEqual(pose.rotations, preceding.rotations,
                                "The floor correction cannot introduce a rotational jump")
                            try assertFloorAndBones(skin, pose: pose)
                        }
                        previous[stage] = pose; previousControl[stage] = controlPose; preceding = pose
                        stageSaved[stage] = pose.rotations.map(\.vector)
                        rows.append(row)
                    }
                    saved.append(skin.model.jointTransforms); savedStages.append(stageSaved)
                }
                XCTAssertGreaterThan(controlMaximumChest, 25, "The control must reproduce the independently measured jump")
                XCTAssertLessThan(maximumChest, controlMaximumChest * 0.4,
                    "Ease the actual native chest, not merely its scalar policy")
                XCTAssertLessThanOrEqual(maximumJoint, controlMaximumJoint + 0.25,
                    "Do not move the discontinuity into another joint")
                rows.append(["edgeSummary": true, "edge": edge, "detail": String(describing: detail),
                    "maximumChestStepDegrees": maximumChest, "controlMaximumChestStepDegrees": controlMaximumChest,
                    "maximumJointStepDegrees": maximumJoint, "controlMaximumJointStepDegrees": controlMaximumJoint])
                for index in times.indices.reversed() {
                    capture.reset(); update(skin, context: context, time: times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                    for stage in Stage.allCases {
                        XCTAssertEqual(capture.stages[stage]!.rotations.map(\.vector), savedStages[index][stage])
                    }
                }
            }
        }
        try attach(rows, name: "NativeStagesBothEdges")
    }

    func testHeaderZeroInfluenceEndpointsAndShrinkingEpsilonBaseline() async throws {
        let context = try await context()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let capture = Capture(); observe(skin, into: capture)
            defer { skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil }
            let watched = try watchedJoints(skin)
            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            for (edge, boundary) in [("entry", context.header.startTime), ("exit", context.header.endTime)] {
                var endpoint = metadata(context, time: boundary)
                endpoint["zeroInfluenceEndpoint"] = true; endpoint["edge"] = edge
                endpoint["detail"] = String(describing: detail)
                endpoint["scope"] = "Endpoint is diagnosed separately, not included in contact-preservation hashes"
                rows.append(endpoint)
                for epsilon in [1.0 / 120, 0.001, 0.0001, 0.00001] {
                    capture.reset(); update(skin, context: context, time: boundary - epsilon)
                    let before = capture.stages, beforeFinal = skin.model.jointTransforms
                    capture.reset(); update(skin, context: context, time: boundary + epsilon)
                    let after = capture.stages, afterFinal = skin.model.jointTransforms
                    for stage in Stage.allCases {
                        let a = try XCTUnwrap(before[stage]), b = try XCTUnwrap(after[stage])
                        let deltas = watched.map { angle(a.rotations[$0], b.rotations[$0]) }
                        XCTAssertTrue(deltas.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 180 })
                        if epsilon == 0.00001 {
                            XCTAssertLessThan(angle(a.rotations[chest], b.rotations[chest]), 0.2,
                                "The chest difference must vanish across the exact entry/exit join")
                            XCTAssertLessThan(try XCTUnwrap(deltas.max()), 0.3,
                                "No near-zero boundary jump may be transferred to the arms or head")
                        }
                        rows.append(["edge": edge, "detail": String(describing: detail), "stage": stage.rawValue,
                            "boundaryTime": boundary, "epsilonSeconds": epsilon,
                            "before": metadata(context, time: boundary - epsilon),
                            "after": metadata(context, time: boundary + epsilon),
                            "jointIndices": watched, "jointNames": watched.map { skin.motion.joints[$0].name },
                            "watchedJointDeltaDegrees": deltas,
                            "chestDeltaDegrees": angle(a.rotations[chest], b.rotations[chest])])
                    }
                    update(skin, context: context, time: boundary - epsilon)
                    XCTAssertEqual(skin.model.jointTransforms, beforeFinal)
                    update(skin, context: context, time: boundary + epsilon)
                    XCTAssertEqual(skin.model.jointTransforms, afterFinal)
                }
            }
        }
        try attach(rows, name: "ZeroEndpointsAndBoundaryLimits")
    }

    func testMeaningfulHeaderAndFullSupportCoreIndependentBaselineReceipts() async throws {
        let context = try await context()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let capture = Capture(); observe(skin, into: capture)
            defer { skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil }
            var positiveHash = SHA256(), supportHash = SHA256(), sourceHash = SHA256()
            var positiveCount = 0, supportCount = 0
            var times: [Double] = [], poses: [[Transform]] = []
            for index in 1..<Int(ceil((context.header.endTime - context.header.startTime) * 120)) {
                let time = context.header.startTime + Double(index) / 120
                let action = ReplayAthleteInteractionPose.sample(cue: context.header, at: time, track: context.track,
                    presentationPose: context.track.presentationPose(at: time))
                guard let action, action.influence >= 0.0001 else { continue }
                capture.reset(); update(skin, context: context, time: time)
                let source = try XCTUnwrap(capture.stages[.source])
                feed(skin.model.jointTransforms, time: time, into: &positiveHash)
                feed(source, time: time, into: &sourceHash)
                positiveCount += 1
                let fullSupport = time >= context.header.contactTime - 0.055 && time <= context.header.contactTime + 0.070
                if fullSupport {
                    XCTAssertEqual(action.influence, 1)
                    supportCount += 1; feed(skin.model.jointTransforms, time: time, into: &supportHash)
                }
                try assertFloorAndBones(skin, pose: skin.pose)
                rows.append(["detail": String(describing: detail), "preservedTime": time,
                    "interactionInfluence": action.influence, "fullPhysicalSupport": fullSupport,
                    "ballPosition": vector(context.recording.sample(at: time).position)])
                times.append(time); poses.append(skin.model.jointTransforms)
            }
            for index in times.indices.reversed() {
                update(skin, context: context, time: times[index])
                XCTAssertEqual(skin.model.jointTransforms, poses[index])
            }
            XCTAssertGreaterThan(positiveCount, 70); XCTAssertGreaterThan(supportCount, 10)
            let frozen = try XCTUnwrap(expected[String(describing: detail)])
            XCTAssertEqual(positiveCount, 87); XCTAssertEqual(supportCount, 15)
            XCTAssertEqual(hex(positiveHash), frozen.positive)
            XCTAssertEqual(hex(supportHash), frozen.support)
            XCTAssertEqual(hex(sourceHash), expectedSource)
            rows.append(["baselineHashes": true, "detail": String(describing: detail),
                "meaningfulPositiveInfluenceSamples": positiveCount, "fullSupportSamples": supportCount,
                "positivePoseSHA256": hex(positiveHash), "fullSupportPoseSHA256": hex(supportHash),
                "sourcePoseSHA256": hex(sourceHash),
                "scope": "Frozen independent pre-fix hashes; zero-influence endpoints excluded"])
        }
        var ballHash = SHA256()
        for index in 0...Int(context.scenario.duration * 120) {
            let time = Double(index) / 120, ball = context.recording.sample(at: time)
            ballHash.update(data: Data("\(time.bitPattern):\(ball.position.x.bitPattern),\(ball.position.y.bitPattern),\(ball.position.z.bitPattern);".utf8))
        }
        rows.append(["ballBaseline": true, "scenario": context.scenario.id,
            "samples120Hz": Int(context.scenario.duration * 120) + 1,
            "positionSHA256": hex(ballHash), "nativeTouches": context.recording.touches.map {
                ["player": $0.playerID, "time": $0.time, "kind": $0.kind.rawValue,
                 "position": vector($0.position), "outgoingVelocity": vector($0.outgoingVelocity)] as [String: Any]
            }])
        XCTAssertEqual(hex(ballHash), expectedBall)
        try attach(rows, name: "IndependentContactSourceAndBallReceipts")
    }

    func testDefaultOverridesNoHeaderAndOtherTouchRemainByteExact() async throws {
        let context = try await context()
        var otherTouchSamples = 0
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let control = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            control.disablesHeaderHandoffForTesting = true
            for time in [0, 3.5, 6.8, 7.05, 7.30, 7.358333333333333, 7.55, 8, 10] {
                XCTAssertNotEqual(context.cue(at: time)?.kind, .header)
                if context.cue(at: time) != nil { otherTouchSamples += 1 }
                update(skin, context: context, time: time); update(control, context: context, time: time)
                XCTAssertEqual(skin.model.jointTransforms, control.model.jointTransforms)
            }
            for (speed, turn) in [(Float(1.1), Float(0)), (3.6, 0), (3, 180)] {
                let time = 4.25
                let supplied = PlayerLocomotionSample(motion: context.track.motion(at: time),
                    speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
                    turnRateDegreesPerSecond: turn,
                    state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: turn))
                for actor in [skin, control] {
                    XCTAssertTrue(actor.update(at: time, track: context.track, locomotion: supplied,
                        lookTarget: nil, ballAction: nil))
                }
                XCTAssertEqual(skin.model.jointTransforms, control.model.jointTransforms,
                    "No implicit header or track sampling may alter a caller's default override")
            }
        }
        XCTAssertGreaterThan(otherTouchSamples, 0)
    }

    func testCaptureMatchedNativeHeaderEntryAndExitNearLow() async throws {
        let context = try await context()
        let calibration = try await calibrate()
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            for (edge, boundary) in [("entry", context.header.startTime), ("exit", context.header.endTime)] {
                let centre = context.track.presentationPose(at: boundary).position
                let origin = SIMD3<Float>(centre.x, 0, centre.z)
                let first = floor(boundary * 120) / 120
                for time in [first, first + 1.0 / 120] {
                    for legacy in [true, false] {
                        let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
                        skin.disablesHeaderHandoffForTesting = legacy
                        update(skin, context: context, time: time)
                        let presented = context.track.presentationPose(at: time)
                        let scene = Entity(), actor = Entity()
                        actor.position = SIMD3<Float>(presented.position.x, 0, presented.position.z) - origin
                        actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                        actor.addChild(skin.root); scene.addChild(actor)
                        defer {
                            skin.root.removeFromParent()
                            for child in Array(scene.children) { child.removeFromParent() }
                        }
                        let floor = ModelEntity(mesh: .generateBox(size: [8, 0.008, 8]),
                            materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                                       roughness: 1, isMetallic: false)])
                        floor.position.y = -0.006; scene.addChild(floor)
                        let ball = ModelEntity(mesh: .generateSphere(radius: 0.11),
                            materials: [SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)])
                        ball.position = context.recording.sample(at: time).position - origin; scene.addChild(ball)
                        let camera = PerspectiveCamera()
                        camera.camera = .init(near: 0.05, far: 80, fieldOfViewInDegrees: 35)
                        camera.look(at: [0, 0.8, 0], from: [4, 2, -3.2], relativeTo: nil)
                        let key = DirectionalLight(), fill = DirectionalLight()
                        key.light.intensity = 2_200; key.look(at: [0, 0.8, 0], from: [3, 4, -3], relativeTo: nil)
                        fill.light.intensity = 500; fill.look(at: [0, 0.8, 0], from: [-3, 2, -2], relativeTo: nil)
                        let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                        let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                                  uniformTypeIdentifier: "public.png")
                        image.name = "ReplayXI-HeaderHandoff141-\(edge)-\(detail)-\(time)-\(legacy ? "legacy" : "candidate").png"
                        image.lifetime = .keepAlways; add(image)
                    }
                }
            }
        }
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for index in ReplayRealityRendererAudit.swatches.indices {
            let color = try XCTUnwrap(CGColor(colorSpace: space,
                components: ReplayRealityRendererAudit.swatches[index].map { CGFloat($0) / 255 } + [1]))
            let tile = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            tile.position = ReplayRealityRendererAudit.swatchPosition(index); root.addChild(tile)
        }
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90); camera.position = [0, 0, 2]
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
        let done = expectation(description: "Header handoff native frame"), flag = Header141RenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); done.fulfill() })
        await fulfillment(of: [done], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Header frame timed out") }
        return try withExtendedLifetime((renderer, entities, camera, output)) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func assertFloorAndBones(_ skin: ReplaySkinnedAthleteInstance, pose: ReplaySkinnedAthleteMotion.Pose) throws {
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: pose) - skin.motion.geometry.restMinY,
            skin.contactSurface.paddingMetres - 0.0001)
        for side in ["left", "right"] {
            for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                let actual = simd_distance(pose.modelSpaceTransforms[a].columns.3, pose.modelSpaceTransforms[b].columns.3)
                let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                XCTAssertEqual(actual, rest, accuracy: 0.0002)
            }
        }
    }

    private func feed(_ transforms: [Transform], time: Double, into hash: inout SHA256) {
        hash.update(data: Data("\(time.bitPattern):".utf8))
        for transform in transforms {
            for value in vector(transform.translation) + vector(transform.rotation.vector) + vector(transform.scale) {
                hash.update(data: Data("\(value.bitPattern),".utf8))
            }
        }
    }

    private func feed(_ pose: ReplaySkinnedAthleteMotion.Pose, time: Double, into hash: inout SHA256) {
        feed(pose.rotations.indices.map { Transform(scale: pose.scales[$0], rotation: pose.rotations[$0],
                                                    translation: pose.translations[$0]) }, time: time, into: &hash)
    }

    private func hex(_ hash: SHA256) -> String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi
    }
    private func vector(_ value: SIMD4<Float>) -> [Float] { [value.x, value.y, value.z, value.w] }
    private func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }
    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-HeaderHandoff141-\(name).json"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
