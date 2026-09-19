import CoreGraphics
import CryptoKit
import Foundation
import RealityKit
import simd
import UIKit
import XCTest
@testable import ReplayXI

private final class SlowRunRenderCompletion150: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

/// Test-data substitution only. No production source, clock, route, asset,
/// contact solver or quality policy changes. A low moving point is not contact.
@MainActor
final class ReplaySlowRunAB150Tests: XCTestCase {
    private typealias Probe = ReplayArmLOD147Probe
    private typealias Skin = ReplaySkinnedAthleteInstance
    private typealias Pose = ReplaySkinnedAthleteMotion.Pose
    private let fixtureHash = "81633d787043a30cff0b86ef5272542522d619b7bc9186c7105d75a489bf3062"
    private let frames = Array(30...96)
    private final class Stages {
        var poses: [Skin.DiagnosticStage: Pose] = [:]
        var phaseWeight: Float = 0
        var retargetInfluence: Float = 0
        func clear() { poses.removeAll(keepingCapacity: true); phaseWeight = 0; retargetInfluence = 0 }
    }
    private struct Point {
        struct Influence { let joint: Int; let point: SIMD4<Float>; let weight: Float }
        let id: String
        let influences: [Influence]
    }
    private struct Sample {
        let frame: Int
        let actor: Transform
        let joints: [Transform]
        let chain: [Transform]
        let points: [SIMD3<Float>]
    }
    private struct Patch {
        let points: [Point]
        let anatomical: String
        init(_ skin: Skin, semantic: String) throws {
            let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[semantic + "Ankle"])
            let hips = try XCTUnwrap(skin.motion.semanticJointIndices["hips"])
            anatomical = skin.motion.restPose.modelSpaceTransforms[ankle].columns.3.x
                < skin.motion.restPose.modelSpaceTransforms[hips].columns.3.x ? "left" : "right"
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            XCTAssertEqual(skeleton.joints.map(\.name), skin.motion.jointNames)
            let allowed = Set(skin.motion.joints.indices.filter { index in
                var cursor = index
                while cursor >= 0 {
                    if cursor == ankle { return true }
                    cursor = skin.motion.joints[cursor].parentIndex
                }
                return false
            })
            var result: [Point] = []
            for (partIndex, part) in contents.models.flatMap({ Array($0.parts) }).enumerated() {
                let weights = try XCTUnwrap(part.jointInfluences).influences.elements
                guard part.positions.count > 0, weights.count.isMultiple(of: part.positions.count) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let width = weights.count / part.positions.count
                guard (1...8).contains(width) else { throw CocoaError(.fileReadCorruptFile) }
                for (index, position) in part.positions.elements.enumerated() {
                    let slice = weights[(index * width)..<((index + 1) * width)].filter { $0.weight > 0 }
                    guard !slice.isEmpty, slice.allSatisfy({ allowed.contains($0.jointIndex) }) else { continue }
                    let influences = slice.map { Point.Influence(joint: $0.jointIndex,
                        point: skeleton.joints[$0.jointIndex].inverseBindPoseMatrix * SIMD4(position, 1), weight: $0.weight) }
                    let rest = influences.reduce(SIMD4<Float>.zero) {
                        $0 + skin.motion.restPose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                    }
                    guard rest.y <= skin.motion.geometry.restMinY + 0.04 else { continue }
                    XCTAssertEqual(rest.w, 1, accuracy: 0.00001)
                    result.append(.init(id: "part\(partIndex):v\(index)", influences: influences))
                }
            }
            XCTAssertGreaterThan(result.count, 3)
            points = result
        }
        func positions(_ pose: Pose, matrix: simd_float4x4) -> [SIMD3<Float>] {
            points.map { point in
                let model = point.influences.reduce(SIMD4<Float>.zero) {
                    $0 + pose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                }
                let pitch = matrix * model
                return [pitch.x, pitch.y, pitch.z]
            }
        }
    }

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        if let scenario = FootballReferenceScenarios.all.first(where: { $0.id == "final-108-rebound-v2" }) {
            let root = Entity(), marks = Entity(); marks.name = "marks-root"; root.addChild(marks)
            PitchSceneFactory.update(root: root, scenario: scenario, time: 0, viewMode: .firstPerson,
                perspectiveID: "arg-10", marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, playerDetail: .fullSquad)
            for child in Array(root.children) { child.removeFromParent() }
        }
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testActualReboundSlowRunSourceABNearLowFixedBootsAndNativeFrames150() async throws {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let slow = try loadSlowFixture()
        let context = try await Probe.context()
        try ReplayAthleteFactory.prewarm(for: context.scenario.players, lods: [.near, .far])
        let originalPlayers = context.scenario.players, originalBall = context.scenario.ball
        let positions = context.recording.samples.map(\.position), velocities = context.recording.samples.map(\.velocity)
        let orientations = context.recording.samples.map { $0.orientation.vector }
        let calibration = try await calibrate()
        let calibrationReceipt = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        calibrationReceipt.name = "ReplayXI-SlowRun150-Calibration.json"; calibrationReceipt.lifetime = .keepAlways; add(calibrationReceipt)
        var cases: [[String: Any]] = [], images: [[String: Any]] = [], bytes = 0
        for id in ["arg-13", "arg-19"] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let result = try await measure(context, id: id, detail: detail, slow: slow, calibration: calibration)
                cases.append(contentsOf: result.rows); images.append(contentsOf: result.images); bytes += result.bytes
            }
        }
        XCTAssertEqual(cases.count, 8); XCTAssertEqual(images.count, 24)
        XCTAssertLessThanOrEqual(bytes, 48 * 1_024 * 1_024)
        XCTAssertEqual(context.scenario.players, originalPlayers); XCTAssertEqual(context.scenario.ball, originalBall)
        XCTAssertEqual(context.recording.samples.map(\.position), positions)
        XCTAssertEqual(context.recording.samples.map(\.velocity), velocities)
        XCTAssertEqual(context.recording.samples.map { $0.orientation.vector }, orientations)
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let receipt: [String: Any] = ["scenario": context.scenario.id, "cases": cases, "images": images,
            "framesPerCase": frames.count, "sampleRateHz": 120, "pngBytes": bytes,
            "fixtureSHA256": fixtureHash, "fastSHA256": ReplaySkinnedAthleteProvider.motionSHA256,
            "slowPhaseShiftRadians": 0,
            "scope": "Two separate native actor instances with the actual factory actor transform. Fast standalone joints equal the factory oracle before every comparison; slow changes only its run clip. Same track phase/clock, routes, native ball, shared material resources, camera and lights. The factory oracle is hidden only for matched captures. No production change or contact correction.",
            "phaseScope": "Intact unshifted slow source. Independent source study found less than 0.34 percent balanced-body RMS improvement at minus five degrees. Production source-specific cut phase and cut smoothing admission are asserted zero here; no inference about faster cuts or protected contacts.",
            "limits": "The source supplies no measured contact. Fixed rest-bottom-40mm boot vertices, not a changing lowest point. Near-floor paths include roll and toe motion. Fast-baseline comparison windows are not asserted to be slow support windows."]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SlowRun150-NativeSourceAB.json"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func loadSlowFixture() throws -> ReplaySkinnedAthleteMotion {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = repository.appendingPathComponent("ReplayXITests/Fixtures/Generated/ReplayXIRocketboxSlowRun150.json")
        let data = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), fixtureHash)
        let original = try Data(contentsOf: repository.appendingPathComponent("ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"))
        XCTAssertEqual(SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(), ReplaySkinnedAthleteProvider.motionSHA256)
        var slowJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var fastJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let slowClips = try XCTUnwrap(slowJSON.removeValue(forKey: "clips") as? [[String: Any]])
        let fastClips = try XCTUnwrap(fastJSON.removeValue(forKey: "clips") as? [[String: Any]])
        XCTAssertTrue(try JSONSerialization.data(withJSONObject: slowJSON, options: [.sortedKeys])
            == JSONSerialization.data(withJSONObject: fastJSON, options: [.sortedKeys]), "Only the run clip may differ")
        XCTAssertTrue(try JSONSerialization.data(withJSONObject: slowClips.filter { ($0["id"] as? String) == "idle" }, options: [.sortedKeys])
            == JSONSerialization.data(withJSONObject: fastClips.filter { ($0["id"] as? String) == "idle" }, options: [.sortedKeys]), "Idle clip must remain exact")
        let slow = try ReplaySkinnedAthleteMotion(data: data)
        let fast = try XCTUnwrap(ReplaySkinnedAthleteProvider.motion)
        XCTAssertEqual(slow.jointNames, fast.jointNames); XCTAssertEqual(slow.joints.count, 80)
        XCTAssertEqual(slow.restPose.translations, fast.restPose.translations)
        XCTAssertEqual(slow.restPose.rotations.map(\.vector), fast.restPose.rotations.map(\.vector))
        XCTAssertEqual(slow.restPose.scales, fast.restPose.scales)
        for time in [0.0, 0.25, 0.5, 0.8] {
            var a = slow.makePoseBuffer(), b = fast.makePoseBuffer()
            slow.sample(clip: .idle, at: time, into: &a); fast.sample(clip: .idle, at: time, into: &b)
            XCTAssertEqual(a.translations, b.translations); XCTAssertEqual(a.rotations.map(\.vector), b.rotations.map(\.vector))
            XCTAssertEqual(a.scales, b.scales)
        }
        return slow
    }

    private func measure(_ context: Probe.Context, id: String, detail: ReplaySkinnedAthleteProvider.Detail,
                         slow: ReplaySkinnedAthleteMotion, calibration: ReplayRealityRendererAudit.Calibration) async throws
        -> (rows: [[String: Any]], images: [[String: Any]], bytes: Int) {
        let track = try XCTUnwrap(context.scenario.player(id: id)), wearer = detail == .near ? "arg-23" : "arg-10"
        let detailName = detail == .near ? "near" : "low"
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, context: context, wearer: wearer, frame: frames[0])
        let oracle = try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[id])
        XCTAssertEqual(oracle.detail, detail)
        let oracleActor = try XCTUnwrap(oracle.root.parent)
        XCTAssertEqual(oracleActor.name, "player-\(id)")
        let playersRoot = try XCTUnwrap(root.findEntity(named: "players-root")), ball = try XCTUnwrap(root.findEntity(named: "ball"))
        XCTAssertTrue(oracleActor.parent === playersRoot); XCTAssertEqual(playersRoot.transform, Transform())
        let fast = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
        // Resource donor is never updated or registered with the factory. The
        // alternate instance is the only writer of this separate native model.
        let slowResources = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
        XCTAssertEqual(slowResources.root.children.count, 1)
        let skinRoot = try XCTUnwrap(slowResources.root.children.first)
        XCTAssertTrue(slowResources.front.parent === skinRoot && slowResources.back.parent === skinRoot)
        XCTAssertTrue(ReplaySkinnedAthleteProvider.skinnedModels(in: skinRoot).first === slowResources.model)
        let candidate = Skin(root: slowResources.root, skinRoot: skinRoot, model: slowResources.model,
            front: slowResources.front, back: slowResources.back, playerID: id, motion: slow,
            contactSurface: slowResources.contactSurface, detail: detail, bootMarkers: slowResources.bootMarkers)
        let fastActor = Entity(), slowActor = Entity()
        fastActor.name = "diagnostic-fast-\(id)"; slowActor.name = "diagnostic-slow-\(id)"
        fastActor.addChild(fast.root); slowActor.addChild(candidate.root)
        root.addChild(fastActor); root.addChild(slowActor)
        fastActor.isEnabled = false; slowActor.isEnabled = false
        XCTAssertFalse(fast.model === oracle.model); XCTAssertFalse(candidate.model === fast.model)
        XCTAssertFalse(candidate.model === oracle.model)
        let patch = try Patch(fast, semantic: id == "arg-13" ? "left" : "right")
        let captureFrames = id == "arg-13" ? [56, 64, 74] : [60, 68, 78]
        let centrePose = track.presentationPose(at: 0.525), centre = SIMD3<Float>(centrePose.position.x, 0, centrePose.position.z)
        let heading = simd_quatf(angle: centrePose.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let camera = PerspectiveCamera(); camera.camera = .init(near: 0.05, far: 30, fieldOfViewInDegrees: 45)
        camera.look(at: centre + [0, 0.9, 0], from: centre + heading.act([id == "arg-13" ? 4 : -4, 1.45, 2]), relativeTo: nil)
        let key = DirectionalLight(); key.light.intensity = 2_200; key.look(at: centre, from: centre + [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight(); fill.light.intensity = 1_000; fill.look(at: centre, from: centre + [-3, 3, -3], relativeTo: nil)
        let grid = grid(centre); root.addChild(grid)
        let fixedCamera = camera.transform, fixedLights = [key.transform, fill.transform], fixedGrid = grid.transform
        let renderer = try RealityRenderer(); renderer.entities.append(contentsOf: [root, camera, key, fill])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 512)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let stages = Stages()
        fast.poseStageObserverForTesting = { stage, pose in stages.poses[stage] = pose }
        candidate.poseStageObserverForTesting = { stage, pose in stages.poses[stage] = pose }
        fast.authoredPoseObserverForTesting = { _, phase, influence in stages.phaseWeight = phase; stages.retargetInfluence = influence }
        candidate.authoredPoseObserverForTesting = { _, phase, influence in stages.phaseWeight = phase; stages.retargetInfluence = influence }
        defer {
            fast.poseStageObserverForTesting = nil; candidate.poseStageObserverForTesting = nil
            fast.authoredPoseObserverForTesting = nil; candidate.authoredPoseObserverForTesting = nil
        }
        var saved: [String: [Sample]] = [:], frameRows: [String: [[String: Any]]] = [:]
        var images: [[String: Any]] = [], bytes = 0
        for frame in frames {
            update(root, context: context, wearer: wearer, frame: frame)
            let input = Probe.input(context, player: track, time: Double(frame) / 120)
            XCTAssertEqual(oracleActor.position, [input.presentation.position.x, 0, input.presentation.position.z])
            XCTAssertEqual(oracleActor.scale, SIMD3<Float>(repeating: 1))
            fastActor.transform = oracleActor.transform; slowActor.transform = oracleActor.transform
            let cut = ReplaySkinnedAthleteCutWeight.sample(source: slow.sourceCommit, track: track,
                at: input.time, locomotion: input.locomotion, interaction: nil, enabled: true)
            XCTAssertEqual(cut.admission, 0); XCTAssertEqual(cut.neighbourSamples, 0)
            let expectedBall = context.recording.pose(at: input.time)
            XCTAssertEqual(ball.position, [expectedBall.position.x, max(expectedBall.height, 0.11), expectedBall.position.z])
            let actors = playersRoot.children.map(\.transform), fixedBall = ball.transform
            let peers = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            let peerJoints = peers.mapValues { $0.model.jointTransforms }
            for (variant, skin, actor) in [("fast", fast, fastActor), ("slow", candidate, slowActor)] {
                stages.clear(); Probe.update(skin, player: track, input: input)
                if variant == "fast" {
                    XCTAssertTrue(fast.model.jointTransforms == oracle.model.jointTransforms,
                                  "Standalone baseline must exactly equal actual factory oracle \(id)/\(detailName)/f\(frame)")
                }
                XCTAssertEqual(stages.phaseWeight, 0)
                let final = Probe.submitted(skin), chain = try modelToPitch(skin, actor: actor)
                try assertBonesAndFloor(skin, final)
                let points = patch.positions(final, matrix: chain.matrix)
                if variant == "fast" {
                    XCTAssertEqual(fast.root.transform, oracle.root.transform)
                    let oracleChain = try modelToPitch(oracle, actor: oracleActor)
                    XCTAssertTrue(points == patch.positions(Probe.submitted(oracle), matrix: oracleChain.matrix),
                                  "Exact fixed-patch baseline versus actual factory \(id)/\(detailName)/f\(frame)")
                }
                var stageRows: [String: Any] = [:]
                for stage in [Skin.DiagnosticStage.source, .footballRetargetAndContact, .finalFloor] {
                    var pose = try XCTUnwrap(stages.poses[stage]); skin.motion.rebuildModelSpaceTransforms(in: &pose)
                    let values = patch.positions(pose, matrix: chain.matrix)
                    stageRows[stage.rawValue] = ["centroid": vector(centroid(values)), "minimumY": values.map(\.y).min()!]
                }
                saved[variant, default: []].append(.init(frame: frame, actor: actor.transform,
                    joints: skin.model.jointTransforms, chain: chain.transforms, points: points))
                frameRows[variant, default: []].append(["frame": frame, "time": input.time,
                    "phase": track.gaitPhase(at: input.time), "speed": input.locomotion.speedMetresPerSecond,
                    "actor": vector(actor.position), "stages": stageRows,
                    "actualRetargetInfluence": stages.retargetInfluence, "actualAuthoredCutPhaseWeight": stages.phaseWeight,
                    "cutSmoothingAdmission": cut.admission, "rawCutInfluence": cut.rawInfluence])
                if captureFrames.contains(frame) {
                    oracleActor.isEnabled = false
                    fastActor.isEnabled = variant == "fast"; slowActor.isEnabled = variant == "slow"
                    let halfFOV = tan(Float.pi / 8) * 0.97
                    for height: Float in [0, 2.10] {
                        for x: Float in [-0.75, 0.75] {
                            for z: Float in [-0.75, 0.75] {
                                let projected = camera.convert(position: actor.position + [x, height, z], from: nil)
                                XCTAssertLessThan(projected.z, -0.05)
                                XCTAssertLessThan(abs(projected.x), -projected.z * halfFOV)
                                XCTAssertLessThan(abs(projected.y), -projected.z * halfFOV)
                            }
                        }
                    }
                    try await render(renderer, output: output, name: "Slow run150 \(id)/\(detailName)/\(variant)/\(frame)")
                    let pixels = try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
                    XCTAssertGreaterThan(stride(from: 0, to: pixels.bgra.count, by: 4).filter {
                        max(pixels.bgra[$0], pixels.bgra[$0 + 1], pixels.bgra[$0 + 2]) > 8
                    }.count, 20_000)
                    let png = try ReplayRealityRendererAudit.png(pixels, calibration: calibration); bytes += png.count
                    let name = "ReplayXI-SlowRun150-\(id)-\(detailName)-f\(frame)-\(variant).png"
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                    images.append(["attachment": name, "player": id, "detail": detailName, "variant": variant,
                        "frame": frame, "time": input.time, "camera": vector(camera.position),
                        "cameraTarget": vector(centre + [0, 0.9, 0]), "actorPosition": vector(actor.position),
                        "facingDegrees": input.presentation.facingDegrees, "notMeasuredContact": true])
                    fastActor.isEnabled = false; slowActor.isEnabled = false; oracleActor.isEnabled = true
                }
                XCTAssertEqual(root.transform, Transform()); XCTAssertEqual(camera.transform, fixedCamera)
                XCTAssertEqual([key.transform, fill.transform], fixedLights); XCTAssertEqual(grid.transform, fixedGrid)
                XCTAssertTrue(playersRoot.children.map(\.transform) == actors); XCTAssertEqual(ball.transform, fixedBall)
                XCTAssertEqual(fastActor.transform, oracleActor.transform); XCTAssertEqual(slowActor.transform, oracleActor.transform)
                XCTAssertTrue(skin.model.jointTransforms == saved[variant]!.last!.joints)
                XCTAssertEqual(try modelToPitch(skin, actor: actor).transforms, chain.transforms)
                XCTAssertEqual(patch.positions(Probe.submitted(skin), matrix: chain.matrix), points)
                for (peerID, peer) in peers { XCTAssertTrue(peer.model.jointTransforms == peerJoints[peerID], "Unchanged peer \(peerID)") }
            }
        }
        for (index, frame) in frames.enumerated().reversed() {
            update(root, context: context, wearer: wearer, frame: frame)
            fastActor.transform = oracleActor.transform; slowActor.transform = oracleActor.transform
            for (variant, skin, actor) in [("fast", fast, fastActor), ("slow", candidate, slowActor)] {
                Probe.update(skin, player: track, input: Probe.input(context, player: track, time: Double(frame) / 120))
                let prior = try XCTUnwrap(saved[variant])[index], chain = try modelToPitch(skin, actor: actor)
                XCTAssertTrue(skin.model.jointTransforms == prior.joints, "Exact \(id)/\(detailName)/\(variant) rewind f\(frame)")
                XCTAssertEqual(actor.transform, prior.actor); XCTAssertEqual(chain.transforms, prior.chain)
                XCTAssertEqual(patch.positions(Probe.submitted(skin), matrix: chain.matrix), prior.points)
            }
        }
        let rows = try ["fast", "slow"].map { variant -> [String: Any] in
            let samples = try XCTUnwrap(saved[variant])
            return ["player": id, "detail": detailName, "variant": variant, "anatomicalFoot": patch.anatomical,
                "patchVertices": patch.points.map(\.id), "frames": try XCTUnwrap(frameRows[variant]),
                "wholeWindowNearFloor": summaries(samples, patch: patch),
                "fastBaselineComparisonWindowNearFloor": summaries(samples.filter { captureFrames.first!...captureFrames.last! ~= $0.frame }, patch: patch),
                "maximumJointStep": maximumJointStep(samples, names: fast.motion.jointNames),
                "exactRewind": true, "sameTrackBallPeers": true]
        }
        return (rows, images, bytes)
    }

    private func update(_ root: Entity, context: Probe.Context, wearer: String, frame: Int) {
        PitchSceneFactory.update(root: root, scenario: context.scenario, time: Double(frame) / 120, viewMode: .firstPerson,
            perspectiveID: wearer, marks: context.scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: .fullSquad)
        root.transform = Transform() // Fixed diagnostic pitch, not the wearer's camera.
    }
    private func modelToPitch(_ skin: Skin, actor: Entity) throws -> (matrix: simd_float4x4, transforms: [Transform]) {
        var cursor: Entity? = skin.model, matrix = matrix_identity_float4x4, transforms: [Transform] = []
        var seen = Set<ObjectIdentifier>(), foundRoot = false
        while let entity = cursor, entity !== actor {
            guard transforms.count < 16, seen.insert(ObjectIdentifier(entity)).inserted else { throw CocoaError(.fileReadCorruptFile) }
            matrix = entity.transform.matrix * matrix; transforms.append(entity.transform)
            foundRoot = foundRoot || entity === skin.root; cursor = entity.parent
        }
        guard cursor === actor, foundRoot, skin.root.parent === actor else { throw CocoaError(.fileReadCorruptFile) }
        transforms.append(actor.transform)
        return (actor.transform.matrix * matrix, transforms)
    }
    private func assertBonesAndFloor(_ skin: Skin, _ pose: Pose) throws {
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: pose) - skin.motion.geometry.restMinY,
                                   skin.contactSurface.paddingMetres - 0.0001)
        for side in ["left", "right"] {
            for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0]), b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                XCTAssertEqual(simd_distance(pose.modelSpaceTransforms[a].columns.3, pose.modelSpaceTransforms[b].columns.3),
                    simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3), accuracy: 0.0002)
            }
        }
    }
    private func summaries(_ samples: [Sample], patch: Patch) -> [[String: Any]] {
        guard samples.count > 1 else { return [] }
        return [Float(0.01), 0.02, 0.04].map { band in
            var runs: [(Int, Int, Int, Float)] = []
            for vertex in patch.points.indices {
                var start: Int?
                func flush(_ end: Int) {
                    guard let start, end > start else { return }
                    let path = ((start + 1)...end).reduce(Float(0)) {
                        $0 + xz(samples[$1 - 1].points[vertex], samples[$1].points[vertex])
                    }
                    runs.append((vertex, start, end, path))
                }
                for index in samples.indices {
                    if abs(samples[index].points[vertex].y) <= band { if start == nil { start = index } }
                    else { flush(index - 1); start = nil }
                }
                flush(samples.count - 1)
            }
            return ["bandMetres": band, "subepisodes": runs.count,
                "largestThree": runs.sorted { $0.3 > $1.3 }.prefix(3).map { item -> [String: Any] in
                    let first = samples[item.1], last = samples[item.2]
                    return ["vertex": patch.points[item.0].id, "start": Double(first.frame) / 120, "end": Double(last.frame) / 120,
                        "pathXZ": item.3, "netXZ": xz(first.points[item.0], last.points[item.0]),
                        "rootPathXZ": ((item.1 + 1)...item.2).reduce(Float(0)) { $0 + xz(samples[$1 - 1].actor.translation, samples[$1].actor.translation) },
                        "startPoint": vector(first.points[item.0]), "endPoint": vector(last.points[item.0])]
                }] as [String: Any]
        }
    }
    private func maximumJointStep(_ samples: [Sample], names: [String]) -> [String: Any] {
        var maximum: Float = 0, frame = samples[0].frame, joint = 0
        for index in 1..<samples.count {
            for bone in names.indices {
                let a = simd_normalize(samples[index - 1].joints[bone].rotation.vector)
                let b = simd_normalize(samples[index].joints[bone].rotation.vector)
                let av = SIMD4<Double>(Double(a.x), Double(a.y), Double(a.z), Double(a.w))
                let bv = SIMD4<Double>(Double(b.x), Double(b.y), Double(b.z), Double(b.w))
                let normProduct = sqrt(simd_dot(av, av) * simd_dot(bv, bv))
                guard normProduct.isFinite, normProduct > 0 else { XCTFail("Invalid native quaternion norm"); continue }
                let cosine = min(max(abs(simd_dot(av, bv)) / normProduct, 0), 1)
                let degrees = Float(2 * acos(cosine) * 180 / Double.pi)
                XCTAssertTrue(degrees.isFinite)
                if degrees > maximum { maximum = degrees; frame = samples[index].frame; joint = bone }
            }
        }
        return ["degreesPer120HzStep": maximum, "endingFrame": frame, "joint": names[joint],
                "meaning": "Observed step, not a discontinuity assertion or pass threshold"]
    }
    private func grid(_ centre: SIMD3<Float>) -> Entity {
        let grid = Entity(); grid.name = "slow-run150-static-10cm-grid"
        grid.position = [round(centre.x * 10) / 10, 0.0015, round(centre.z * 10) / 10]
        let mesh = MeshResource.generateBox(size: [3.6, 0.001, 0.004])
        let material = UnlitMaterial(color: UIColor(white: 0.34, alpha: 1), applyPostProcessToneMap: false)
        for index in -18...18 {
            for axis in 0..<2 {
                let line = ModelEntity(mesh: mesh, materials: [material])
                if axis == 0 { line.position.z = Float(index) * 0.1 }
                else { line.position.x = Float(index) * 0.1; line.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) }
                if index.isMultiple(of: 5) { line.scale.z = 2 }
                XCTAssertNil(line.components[CollisionComponent.self]); grid.addChild(line)
            }
        }
        return grid
    }
    private func configure(_ renderer: RealityRenderer, camera: Entity) {
        renderer.activeCamera = camera; renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    }
    private func render(_ renderer: RealityRenderer, output: RealityRenderer.CameraOutput, name: String) async throws {
        let completed = expectation(description: name), flag = SlowRunRenderCompletion150()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); completed.fulfill() })
        await fulfillment(of: [completed], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Slow run native frame timed out") }
    }
    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity(); defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]), materials: [UnlitMaterial(color: UIColor(cgColor: colour), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index); root.addChild(swatch)
        }
        let camera = PerspectiveCamera(); camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90); camera.position = [0, 0, 2]
        let renderer = try RealityRenderer(); renderer.entities.append(contentsOf: [root, camera])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }; configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 256)
        try await render(renderer, output: try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture)), name: "Slow run150 calibration")
        let probe = try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.probe(ReplayRealityRendererAudit.read(texture)) }
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }; XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }
    private func vector(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }
    private func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> { points.reduce(.zero, +) / Float(points.count) }
    nonisolated private func xz(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { hypot(a.x - b.x, a.z - b.z) }
}
