import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Shared by the numerical probe and matched native captures. These are the
/// actual demo inputs and submitted rigs, not a substitute elbow-angle pose.
@MainActor
enum ReplayArmLOD147Probe {
    struct Context {
        let scenario: ReplayScenario
        let recording: ReplayNativeBallPhysics.Recording
    }

    struct Input {
        let time: Double
        let presentation: PlayerPose
        let locomotion: PlayerLocomotionSample
        let look: SIMD3<Float>
        let ball: ReplayNativeBallPhysics.Sample
    }

    struct Arm: Equatable {
        let shoulder: SIMD3<Float>
        let elbow: SIMD3<Float>
        let wrist: SIMD3<Float>
        var upper: SIMD3<Float> { elbow - shoulder }
        var lower: SIMD3<Float> { wrist - elbow }
        var bend: Float { ReplayArmLOD147Probe.directionAngle(upper, lower) }
        var normalizedReach: SIMD3<Float> {
            (wrist - shoulder) / (simd_length(upper) + simd_length(lower))
        }
        var row: [String: Any] {
            ["shoulder": ReplayArmLOD147Probe.vector(shoulder),
             "elbow": ReplayArmLOD147Probe.vector(elbow), "wrist": ReplayArmLOD147Probe.vector(wrist),
             "bendDegrees": bend, "upperLengthMetres": simd_length(upper),
             "lowerLengthMetres": simd_length(lower),
             "normalizedReach": ReplayArmLOD147Probe.vector(normalizedReach)]
        }
    }

    static func prepare() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
    }

    static func context() async throws -> Context {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.missedTouchCount, 0)
        for id in ["arg-13", "arg-19"] {
            XCTAssertFalse(recording.touches.contains { $0.playerID == id })
        }
        return .init(scenario: scenario, recording: recording)
    }

    static func input(_ context: Context, player: PlayerTrack, time: Double) -> Input {
        let presentation = player.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let ball = context.recording.sample(at: time)
        let look = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: presentation,
            ball: ball.position, players: context.scenario.players, poses: poses, contacts: [])
        return .init(time: time, presentation: presentation, locomotion: player.locomotion(at: time),
                     look: look, ball: ball)
    }

    static func update(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack, input: Input) {
        XCTAssertTrue(skin.update(at: input.time, track: player, locomotion: input.locomotion,
            lookTarget: input.look, ballAction: nil, presentationPose: input.presentation,
            allowsTrackLocomotionSampling: true))
    }

    static func update(_ far: ReplayAthleteInstance, player: PlayerTrack, input: Input) {
        let pose = ReplayAthleteMotion.locomotionPose(for: player, at: input.time,
            locomotion: input.locomotion, gaitPhase: player.gaitPhase(at: input.time),
            lookTargetWorldPosition: input.look, presentationPose: input.presentation)
        ReplayAthleteMotion.apply(pose, to: far.joints)
    }

    static func submitted(_ skin: ReplaySkinnedAthleteInstance) -> ReplaySkinnedAthleteMotion.Pose {
        var pose = skin.pose
        for (index, transform) in skin.model.jointTransforms.enumerated() {
            pose.translations[index] = transform.translation
            pose.rotations[index] = transform.rotation
            pose.scales[index] = transform.scale
        }
        skin.motion.rebuildModelSpaceTransforms(in: &pose)
        return pose
    }

    static func arms(_ skin: ReplaySkinnedAthleteInstance, pose original: ReplaySkinnedAthleteMotion.Pose,
                     relativeTo actor: Entity) throws -> [Arm] {
        var pose = original
        skin.motion.rebuildModelSpaceTransforms(in: &pose)
        var result: [Bool: Arm] = [:]
        for semantic in ["left", "right"] {
            let binding = try XCTUnwrap(ReplayAthleteOffBallPose.NativeArmBinding(side: semantic, motion: skin.motion))
            func point(_ suffix: String) throws -> SIMD3<Float> {
                let index = try XCTUnwrap(skin.motion.semanticJointIndices[semantic + suffix])
                let p = pose.modelSpaceTransforms[index].columns.3
                return skin.model.convert(position: [p.x, p.y, p.z], to: actor)
            }
            result[binding.isLeft] = try .init(shoulder: point("Shoulder"), elbow: point("Elbow"), wrist: point("Wrist"))
        }
        return try [XCTUnwrap(result[true]), XCTUnwrap(result[false])]
    }

    static func arms(_ far: ReplayAthleteInstance, relativeTo actor: Entity) throws -> [Arm] {
        XCTAssertNotNil(far.joints.articulatedFar, "Probe must use the admitted articulated far mesh")
        let definitions: [(String, ReplayAthleteJoint, ReplayAthleteJoint, ReplayAthleteJoint)] = [
            ("left-arm", .leftShoulder, .leftElbow, .leftWrist),
            ("right-arm", .rightShoulder, .rightElbow, .rightWrist)
        ]
        return try definitions.map { name, shoulder, elbow, wrist in
            let model = try XCTUnwrap(far.joints[shoulder].children.first { $0.name == name } as? ModelEntity)
            XCTAssertEqual(model.jointNames, ["Root", "Root/Bend", "Root/Bend/Tip"])
            let joints = model.jointTransforms
            XCTAssertEqual(joints.count, 3)
            let root = joints[0].matrix
            let bend = root * joints[1].matrix
            let tip = bend * joints[2].matrix
            func point(_ matrix: simd_float4x4) -> SIMD3<Float> {
                let p = matrix.columns.3
                return model.convert(position: [p.x, p.y, p.z], to: actor)
            }
            let arm = Arm(shoulder: point(root), elbow: point(bend), wrist: point(tip))
            for (actual, joint) in [(arm.shoulder, shoulder), (arm.elbow, elbow), (arm.wrist, wrist)] {
                XCTAssertLessThan(simd_distance(actual, far.joints[joint].position(relativeTo: actor)), 0.00001,
                                  "Visible far mesh and articulated entities must agree")
            }
            return arm
        }
    }

    static func comparison(_ native: Arm, _ far: Arm) -> [String: Any] {
        ["native": native.row, "far": far.row, "bendGapDegrees": native.bend - far.bend,
         "upperDirectionGapDegrees": directionAngle(native.upper, far.upper),
         "lowerDirectionGapDegrees": directionAngle(native.lower, far.lower),
         "shoulderGapMetres": simd_distance(native.shoulder, far.shoulder),
         "elbowGapMetres": simd_distance(native.elbow, far.elbow),
         "wristGapMetres": simd_distance(native.wrist, far.wrist),
         "shoulderRelativeWristGapMetres": simd_distance(native.wrist - native.shoulder, far.wrist - far.shoulder),
         "normalizedReachGap": simd_distance(native.normalizedReach, far.normalizedReach)]
    }

    nonisolated static func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }
    nonisolated static func directionAngle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        acos(min(max(simd_dot(simd_normalize(a), simd_normalize(b)), -1), 1)) * 180 / .pi
    }
}

/// Baseline only: a LOD pose gap is not itself proof either arm pose is wrong.
@MainActor
final class ReplayArmLOD147Tests: XCTestCase {
    private typealias Probe = ReplayArmLOD147Probe
    private final class Stages { var poses: [ReplaySkinnedAthleteInstance.DiagnosticStage: ReplaySkinnedAthleteMotion.Pose] = [:] }

    override func tearDown() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testActualReboundNearLowFarSubmittedArmsStagesAndRewind147() async throws {
        try Probe.prepare()
        let context = try await Probe.context()
        let frames = Array(30...96) // 0.25...0.8 s, inclusive, 120 Hz.
        var rows: [[String: Any]] = []
        for id in ["arg-13", "arg-19"] {
            let player = try XCTUnwrap(context.scenario.player(id: id))
            try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
            let far = try ReplayAthleteFactory.make(for: player, lod: .far)
            let actor = Entity(); actor.addChild(far.root)
            defer { for child in Array(actor.children) { child.removeFromParent() } }
            var savedFar: [[Transform]] = []
            var farArms: [[Probe.Arm]] = []
            for frame in frames {
                let input = Probe.input(context, player: player, time: Double(frame) / 120)
                Probe.update(far, player: player, input: input)
                savedFar.append(ReplayAthleteJoint.allCases.map { far.joints[$0].transform })
                farArms.append(try Probe.arms(far, relativeTo: actor))
            }
            for (index, frame) in frames.enumerated().reversed() {
                Probe.update(far, player: player, input: Probe.input(context, player: player, time: Double(frame) / 120))
                XCTAssertEqual(ReplayAthleteJoint.allCases.map { far.joints[$0].transform }, savedFar[index])
                XCTAssertEqual(try Probe.arms(far, relativeTo: actor), farArms[index])
            }
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                actor.addChild(skin.root)
                let stages = Stages()
                skin.poseStageObserverForTesting = { stage, pose in stages.poses[stage] = pose }
                defer { skin.poseStageObserverForTesting = nil; skin.root.removeFromParent() }
                var saved: [[Transform]] = []
                var previous: [Probe.Arm]?
                var maximumWristStep: Float = 0, maximumBendStep: Float = 0
                var maximumBendGap: Float = 0, maximumWristGap: Float = 0
                var nativeBends = [[Float](), [Float]()]
                for (index, frame) in frames.enumerated() {
                    let time = Double(frame) / 120
                    let input = Probe.input(context, player: player, time: time)
                    let ballBefore = context.recording.sample(at: time)
                    Probe.update(skin, player: player, input: input)
                    let actual = try Probe.arms(skin, pose: Probe.submitted(skin), relativeTo: actor)
                    saved.append(skin.model.jointTransforms)
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                                skin.contactSurface.paddingMetres - 0.0001)
                    var stageRows: [[String: Any]] = []
                    for stage in [ReplaySkinnedAthleteInstance.DiagnosticStage.source, .footballRetargetAndContact, .offBall, .finalFloor] {
                        let pose = try XCTUnwrap(stages.poses[stage])
                        let arms = try Probe.arms(skin, pose: pose, relativeTo: actor)
                        stageRows.append(["stage": String(describing: stage), "left": arms[0].row, "right": arms[1].row])
                    }
                    for side in 0..<2 {
                        nativeBends[side].append(actual[side].bend)
                        maximumBendGap = max(maximumBendGap, abs(actual[side].bend - farArms[index][side].bend))
                        maximumWristGap = max(maximumWristGap, simd_distance(actual[side].wrist, farArms[index][side].wrist))
                        if let previous {
                            maximumWristStep = max(maximumWristStep, simd_distance(actual[side].wrist, previous[side].wrist))
                            maximumBendStep = max(maximumBendStep, abs(actual[side].bend - previous[side].bend))
                        }
                    }
                    previous = actual
                    let movement = ReplayAthleteMovementIntent.sample(track: player, at: time,
                        presentationPose: input.presentation, lookTarget: input.look)
                    let upperEffort = input.locomotion.effort * min(max(input.locomotion.speedMetresPerSecond / 2.4, 0), 1)
                    let linear = min(max((upperEffort - 0.02) / 0.20, 0), 1)
                    rows.append(["kind": "frame", "scenario": context.scenario.id, "player": id,
                        "detail": String(describing: detail), "time": time, "gaitPhase": player.gaitPhase(at: time),
                        "speedMetresPerSecond": input.locomotion.speedMetresPerSecond,
                        "locomotionState": input.locomotion.state.rawValue, "upperBodyEffort": upperEffort,
                        "sourceRunWeight": linear * linear * (3 - 2 * linear),
                        "readiness": movement?.readiness ?? 0, "directionalWeight": movement?.directionalWeight ?? 0,
                        "stages": stageRows, "left": Probe.comparison(actual[0], farArms[index][0]),
                        "right": Probe.comparison(actual[1], farArms[index][1])])
                    XCTAssertEqual(context.recording.sample(at: time).position, ballBefore.position)
                    XCTAssertEqual(context.recording.sample(at: time).velocity, ballBefore.velocity)
                    if frame == 36 {
                        let foldedSide = id == "arg-13" ? 0 : 1
                        XCTAssertGreaterThan(actual[foldedSide].bend - farArms[index][foldedSide].bend, 50,
                            "Reproduce the existing receipt gap in actual submitted anatomical lanes; not a quality threshold")
                        rows.append(try phaseScan(skin, player: player, input: input, far: farArms[index], actor: actor))
                    }
                }
                for (index, frame) in frames.enumerated().reversed() {
                    Probe.update(skin, player: player, input: Probe.input(context, player: player, time: Double(frame) / 120))
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
                var ranges: [[String: Any]] = []
                for side in 0..<2 {
                    let farBends = farArms.map { $0[side].bend }
                    ranges.append(["side": side == 0 ? "left" : "right",
                        "nativeMinBendDegrees": try XCTUnwrap(nativeBends[side].min()),
                        "nativeMaxBendDegrees": try XCTUnwrap(nativeBends[side].max()),
                        "farMinBendDegrees": try XCTUnwrap(farBends.min()),
                        "farMaxBendDegrees": try XCTUnwrap(farBends.max())])
                }
                rows.append(["kind": "window", "player": id, "detail": String(describing: detail),
                    "start": 0.25, "end": 0.8, "samples": frames.count, "ranges": ranges,
                    "maximumBendGapDegrees": maximumBendGap, "maximumWristGapMetres": maximumWristGap,
                    "maximumNativeWristStepMetres120Hz": maximumWristStep,
                    "maximumNativeBendStepDegrees120Hz": maximumBendStep, "rewindExact": true,
                    "scope": "Actor-local physical endpoints include each rig's actual scale/anatomy; normalized reach separates size. Baseline, not an assertion either pose is wrong."])
            }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-ArmLOD147-ActualEndpointsStagesAndRewind.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    private func phaseScan(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack, input: Probe.Input,
                           far: [Probe.Arm], actor: Entity) throws -> [String: Any] {
        let effort = input.locomotion.effort * min(max(input.locomotion.speedMetresPerSecond / 2.4, 0), 1)
        var pose = skin.motion.makePoseBuffer()
        var bestError = Float.infinity, bestPhase: Float = 0
        var samples: [[String: Any]] = []
        for step in 0..<72 {
            let phase = Float(step) * 2 * .pi / 72
            skin.motion.sample(time: input.time, locomotionEffort: effort, gaitPhase: phase, into: &pose)
            let arms = try Probe.arms(skin, pose: pose, relativeTo: actor)
            let leftError = arms[0].bend - far[0].bend, rightError = arms[1].bend - far[1].bend
            let error = sqrt((leftError * leftError + rightError * rightError) / 2)
            if error < bestError { bestError = error; bestPhase = phase }
            samples.append(["phaseRadians": phase, "leftBendDegrees": arms[0].bend,
                            "rightBendDegrees": arms[1].bend, "twoArmBendRMSEDegrees": error])
        }
        return ["kind": "sourcePhaseScan", "player": player.id, "time": input.time,
            "detail": String(describing: skin.detail), "actualGaitPhase": player.gaitPhase(at: input.time),
            "bestPhaseRadians": bestPhase, "bestTwoArmBendRMSEDegrees": bestError, "samples": samples,
            "scope": "Diagnostic source-only 5-degree phase scan against the actual far frame. No phase offset applied to production; does not optimize orientation, endpoints or ground contact."]
    }
}
