import CryptoKit
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Native regression for the second, unplanted header aim branch. Limits are
/// based on the independently run cycle142 candidate/control measurements.
@MainActor
final class ReplayCityHeaderHandoff142Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage

    private final class Capture {
        var stages: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
    }

    private struct Context {
        let scenario: ReplayScenario
        let player: PlayerTrack
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
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "city-45-overlap-header" })
        let player = try XCTUnwrap(scenario.player(id: "city-9"))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let cues = try recording.touches.filter { $0.playerID == player.id }.map {
            ReplayAthleteInteractionCue(playerID: player.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        let header = try XCTUnwrap(cues.first { $0.kind == .header })
        XCTAssertNil(header.headerSupportLeg, "This fixture must cover the separate unplanted header aim branch")
        return .init(scenario: scenario, player: player, recording: recording, cues: cues, header: header)
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, context: Context, time: Double) {
        let pose = context.player.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let look = ReplayAthleteTacticalAttention.target(for: context.player, at: time, pose: pose,
            ball: context.recording.sample(at: time).position, players: context.scenario.players,
            poses: poses, contacts: context.cues)
        XCTAssertTrue(skin.update(at: time, track: context.player, locomotion: context.player.locomotion(at: time),
            lookTarget: look, ballAction: nil, interaction: context.cue(at: time), presentationPose: pose,
            allowsTrackLocomotionSampling: true))
    }

    private func metadata(_ context: Context, time: Double) -> [String: Any] {
        let cue = context.cue(at: time)
        let sample = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: context.player,
            presentationPose: context.player.presentationPose(at: time))
        return ["time": time, "cuePresent": cue != nil, "samplePresent": sample != nil,
            "interactionInfluence": sample?.influence ?? 0,
            "protection": ReplayAthleteMovementIntent.contactProtection(for: cue, track: context.player, at: time),
            "rawCutInfluence": ReplaySkinnedAthleteFootballPose.influence(
                locomotion: context.player.locomotion(at: time), ballAction: nil),
            "contactTime": context.header.contactTime, "cueStart": context.header.startTime,
            "cueEnd": context.header.endTime, "unplantedHeaderBranch": true]
    }

    func testCityHeaderBothNativeEdgesAndShrinkingLimitsNearLow() async throws {
        let context = try await context()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let candidate = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            let legacy = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            legacy.disablesHeaderHandoffForTesting = true
            let current = Capture(), control = Capture()
            candidate.poseStageObserverForTesting = { stage, pose in current.stages[stage] = pose }
            legacy.poseStageObserverForTesting = { stage, pose in control.stages[stage] = pose }
            defer { candidate.poseStageObserverForTesting = nil; legacy.poseStageObserverForTesting = nil }
            let chest = try XCTUnwrap(candidate.motion.semanticJointIndices["chest"])
            let watched = try ["chest", "neck", "head", "leftShoulder", "leftElbow", "leftWrist",
                               "rightShoulder", "rightElbow", "rightWrist"].map {
                try XCTUnwrap(candidate.motion.semanticJointIndices[$0])
            }
            for (edge, boundary) in [("entry", context.header.startTime), ("exit", context.header.endTime)] {
                let first = Int(floor((boundary - 0.16) * 120)), last = Int(ceil((boundary + 0.16) * 120))
                let times = (first...last).map { Double($0) / 120 }
                var previous: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
                var previousControl: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
                var saved: [[Transform]] = [], savedControl: [[Transform]] = []
                var maximumChest: Float = 0, oldMaximumChest: Float = 0
                var maximumJoint: Float = 0, oldMaximumJoint: Float = 0
                for (frame, time) in times.enumerated() {
                    update(candidate, context: context, time: time); update(legacy, context: context, time: time)
                    try assertSourceAndGeometry(candidate, legacy, current: current, control: control)
                    let action = ReplayAthleteInteractionPose.sample(cue: context.cue(at: time), at: time,
                        track: context.player, presentationPose: context.player.presentationPose(at: time))
                    if let action, action.influence > 0 {
                        XCTAssertEqual(candidate.model.jointTransforms, legacy.model.jointTransforms,
                            "Every positive-influence header frame keeps the original pose")
                    }
                    for stage in Stage.allCases {
                        let pose = try XCTUnwrap(current.stages[stage]), old = try XCTUnwrap(control.stages[stage])
                        if let before = previous[stage], let beforeOld = previousControl[stage] {
                            let deltas = pose.rotations.indices.map { angle(before.rotations[$0], pose.rotations[$0]) }
                            let oldDeltas = old.rotations.indices.map { angle(beforeOld.rotations[$0], old.rotations[$0]) }
                            let peak = try XCTUnwrap(deltas.indices.max { deltas[$0] < deltas[$1] })
                            var row = metadata(context, time: time)
                            row["previousTime"] = times[frame - 1]; row["detail"] = String(describing: detail)
                            row["edge"] = edge; row["stage"] = stage.rawValue
                            row["chestStepDegrees"] = deltas[chest]; row["legacyChestStepDegrees"] = oldDeltas[chest]
                            row["maximumJointStepDegrees"] = deltas[peak]; row["legacyMaximumJointStepDegrees"] = oldDeltas.max()!
                            row["maximumJoint"] = peak; row["maximumJointName"] = candidate.motion.joints[peak].name
                            row["watchedJointNames"] = watched.map { candidate.motion.joints[$0].name }
                            row["watchedJointStepDegrees"] = watched.map { deltas[$0] }
                            row["legacyWatchedJointStepDegrees"] = watched.map { oldDeltas[$0] }
                            rows.append(row)
                            if stage == .finalFloor {
                                maximumChest = max(maximumChest, deltas[chest]); oldMaximumChest = max(oldMaximumChest, oldDeltas[chest])
                                maximumJoint = max(maximumJoint, deltas.max()!); oldMaximumJoint = max(oldMaximumJoint, oldDeltas.max()!)
                            }
                        }
                        previous[stage] = pose; previousControl[stage] = old
                    }
                    saved.append(candidate.model.jointTransforms); savedControl.append(legacy.model.jointTransforms)
                }
                XCTAssertGreaterThan(oldMaximumChest, 20,
                    "The legacy control must reproduce the independently measured header jump")
                XCTAssertLessThan(maximumChest, oldMaximumChest * 0.4,
                    "The native chest hand-off must retain its measured improvement")
                XCTAssertLessThanOrEqual(maximumJoint, oldMaximumJoint + 0.25,
                    "Do not transfer the hand-off defect into another joint")
                rows.append(["edgeSummary": true, "edge": edge, "detail": String(describing: detail),
                    "maximumChestStepDegrees": maximumChest, "legacyMaximumChestStepDegrees": oldMaximumChest,
                    "maximumJointStepDegrees": maximumJoint, "legacyMaximumJointStepDegrees": oldMaximumJoint,
                    "scope": "Measured native regression; same-frame legacy negative control"])
                for index in times.indices.reversed() {
                    update(candidate, context: context, time: times[index]); update(legacy, context: context, time: times[index])
                    XCTAssertEqual(candidate.model.jointTransforms, saved[index])
                    XCTAssertEqual(legacy.model.jointTransforms, savedControl[index])
                }
                for epsilon in [1.0 / 120, 0.001, 0.0001, 0.00001] {
                    update(candidate, context: context, time: boundary - epsilon)
                    update(legacy, context: context, time: boundary - epsilon)
                    let before = current.stages, beforeOld = control.stages
                    update(candidate, context: context, time: boundary + epsilon)
                    update(legacy, context: context, time: boundary + epsilon)
                    try assertSourceAndGeometry(candidate, legacy, current: current, control: control)
                    for stage in Stage.allCases {
                        let a = try XCTUnwrap(before[stage]), b = try XCTUnwrap(current.stages[stage])
                        let oldA = try XCTUnwrap(beforeOld[stage]), oldB = try XCTUnwrap(control.stages[stage])
                        if epsilon == 0.00001 {
                            XCTAssertLessThan(angle(a.rotations[chest], b.rotations[chest]), 0.2)
                            XCTAssertLessThan(try XCTUnwrap(watched.map {
                                angle(a.rotations[$0], b.rotations[$0])
                            }.max()), 0.3, "A near-zero boundary jump must not move to arms or head")
                            if stage == .finalFloor {
                                XCTAssertGreaterThan(angle(oldA.rotations[chest], oldB.rotations[chest]), 20,
                                    "The bypass control must retain the measured non-vanishing discontinuity")
                            }
                        }
                        rows.append(["boundaryLimit": true, "edge": edge, "detail": String(describing: detail),
                            "stage": stage.rawValue, "boundaryTime": boundary, "epsilonSeconds": epsilon,
                            "before": metadata(context, time: boundary - epsilon), "after": metadata(context, time: boundary + epsilon),
                            "chestDeltaDegrees": angle(a.rotations[chest], b.rotations[chest]),
                            "legacyChestDeltaDegrees": angle(oldA.rotations[chest], oldB.rotations[chest]),
                            "maximumWatchedJointDeltaDegrees": watched.map { angle(a.rotations[$0], b.rotations[$0]) }.max()!,
                            "legacyMaximumWatchedJointDeltaDegrees": watched.map { angle(oldA.rotations[$0], oldB.rotations[$0]) }.max()!])
                    }
                }
            }
        }
        try attach(rows, name: "BothEdgesAndBoundaryLimits")
    }

    func testCityActiveHeaderAndPhysicalCoreStayExactToLegacy() async throws {
        let context = try await context()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let candidate = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            let legacy = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            legacy.disablesHeaderHandoffForTesting = true
            let current = Capture(), control = Capture()
            candidate.poseStageObserverForTesting = { stage, pose in current.stages[stage] = pose }
            legacy.poseStageObserverForTesting = { stage, pose in control.stages[stage] = pose }
            defer { candidate.poseStageObserverForTesting = nil; legacy.poseStageObserverForTesting = nil }
            var positive = 0, physicalCore = 0
            var candidateHash = SHA256(), legacyHash = SHA256(), coreHash = SHA256()
            var times: [Double] = [], saved: [[Transform]] = []
            for index in 1..<Int(ceil((context.header.endTime - context.header.startTime) * 120)) {
                let time = context.header.startTime + Double(index) / 120
                let sample = ReplayAthleteInteractionPose.sample(cue: context.header, at: time, track: context.player,
                    presentationPose: context.player.presentationPose(at: time))
                guard let sample, sample.influence > 0 else { continue }
                update(candidate, context: context, time: time); update(legacy, context: context, time: time)
                try assertSourceAndGeometry(candidate, legacy, current: current, control: control)
                XCTAssertEqual(candidate.model.jointTransforms, legacy.model.jointTransforms)
                feed(candidate.model.jointTransforms, time: time, into: &candidateHash)
                feed(legacy.model.jointTransforms, time: time, into: &legacyHash)
                positive += 1
                if time >= context.header.contactTime - 0.055, time <= context.header.contactTime + 0.070 {
                    physicalCore += 1; XCTAssertEqual(sample.influence, 1)
                    feed(candidate.model.jointTransforms, time: time, into: &coreHash)
                }
                times.append(time); saved.append(candidate.model.jointTransforms)
            }
            for index in times.indices.reversed() {
                update(candidate, context: context, time: times[index])
                XCTAssertEqual(candidate.model.jointTransforms, saved[index])
            }
            XCTAssertGreaterThan(positive, 70); XCTAssertGreaterThan(physicalCore, 10)
            XCTAssertEqual(hex(candidateHash), hex(legacyHash))
            rows.append(["detail": String(describing: detail), "positiveSamples": positive,
                "fullPhysicalCoreSamples": physicalCore, "candidatePoseSHA256": hex(candidateHash),
                "legacyPoseSHA256": hex(legacyHash), "physicalCorePoseSHA256": hex(coreHash),
                "sourceAndRewindExact": true, "contactTime": context.header.contactTime,
                "cueStart": context.header.startTime, "cueEnd": context.header.endTime])
        }
        try attach(rows, name: "PositiveAndPhysicalCore")
    }

    private func assertSourceAndGeometry(_ candidate: ReplaySkinnedAthleteInstance, _ legacy: ReplaySkinnedAthleteInstance,
                                         current: Capture, control: Capture) throws {
        let source = try XCTUnwrap(current.stages[.source]), oldSource = try XCTUnwrap(control.stages[.source])
        XCTAssertEqual(source.rotations, oldSource.rotations); XCTAssertEqual(source.translations, oldSource.translations)
        for skin in [candidate, legacy] {
            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                skin.contactSurface.paddingMetres - 0.0001)
            for side in ["left", "right"] {
                for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                    let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                    let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                    let actual = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3, skin.pose.modelSpaceTransforms[b].columns.3)
                    let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                    XCTAssertEqual(actual, rest, accuracy: 0.0002)
                }
            }
        }
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi
    }
    private func feed(_ transforms: [Transform], time: Double, into hash: inout SHA256) {
        hash.update(data: Data("\(time.bitPattern):".utf8))
        for transform in transforms {
            for value in [transform.translation.x, transform.translation.y, transform.translation.z,
                transform.rotation.vector.x, transform.rotation.vector.y, transform.rotation.vector.z, transform.rotation.vector.w,
                transform.scale.x, transform.scale.y, transform.scale.z] {
                hash.update(data: Data("\(value.bitPattern),".utf8))
            }
        }
    }
    private func hex(_ hash: SHA256) -> String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-CityHeaderHandoff142-\(name).json"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
