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

    /// Diagnostic only: a large display-frame delta is not itself a jump.
    /// Subdivide the two measured intervals, then approach their enclosing
    /// source-frame boundaries and nearby track/cue boundaries independently.
    func testCityToeSourceSpansAndBootMotion144() async throws {
        let context = try await context()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json",
                                               subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json"))
        let timeline = try JSONDecoder().decode(ToeTimeline144.self, from: Data(contentsOf: url))
        let run = try XCTUnwrap(timeline.clips.first { $0.id == "run" })
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let candidate = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            let legacy = try ReplaySkinnedAthleteProvider.make(for: context.player, detail: detail)
            legacy.disablesHeaderHandoffForTesting = true
            let current = Capture(), control = Capture()
            candidate.poseStageObserverForTesting = { stage, pose in current.stages[stage] = pose }
            legacy.poseStageObserverForTesting = { stage, pose in control.stages[stage] = pose }
            defer { candidate.poseStageObserverForTesting = nil; legacy.poseStageObserverForTesting = nil }
            let boots = try ToeBootSurface144(skin: candidate)
            let toe = try XCTUnwrap(candidate.motion.semanticJointIndices["rightToe"])
            let ankle = try XCTUnwrap(candidate.motion.semanticJointIndices["rightAnkle"])

            func snapshot(_ time: Double) throws -> ToeSnapshot144 {
                let ballBefore = context.recording.sample(at: time)
                update(candidate, context: context, time: time)
                update(legacy, context: context, time: time)
                try assertSourceAndGeometry(candidate, legacy, current: current, control: control)
                let locomotion = context.player.locomotion(at: time)
                var direct = candidate.motion.makePoseBuffer()
                candidate.motion.sample(time: time,
                    locomotionEffort: locomotion.effort * min(max(locomotion.speedMetresPerSecond / 2.4, 0), 1),
                    gaitPhase: context.player.gaitPhase(at: time), into: &direct)
                let source = try XCTUnwrap(current.stages[.source])
                XCTAssertEqual(source.rotations, direct.rotations)
                XCTAssertEqual(source.translations, direct.translations)
                let action = ReplayAthleteInteractionPose.sample(cue: context.cue(at: time), at: time,
                    track: context.player, presentationPose: context.player.presentationPose(at: time))
                if let action, action.influence > 0 {
                    XCTAssertEqual(candidate.model.jointTransforms, legacy.model.jointTransforms)
                }
                let ballAfter = context.recording.sample(at: time)
                XCTAssertEqual(ballAfter.position, ballBefore.position)
                XCTAssertEqual(ballAfter.orientation, ballBefore.orientation)
                XCTAssertEqual(ballAfter.velocity, ballBefore.velocity)
                XCTAssertEqual(ballAfter.angularVelocity, ballBefore.angularVelocity)
                let placement = context.player.presentationPose(at: time)
                let world = Transform(rotation: simd_quatf(angle: placement.facingDegrees * .pi / 180,
                    axis: [0, 1, 0]), translation: [placement.position.x, 0, placement.position.z]).matrix
                let modelToWorld = world * candidate.model.transformMatrix(relativeTo: nil)
                let vertices = boots.positions(in: candidate.pose, modelToWorld: modelToWorld)
                XCTAssertTrue(vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(vertices.map(\.y).min()), -0.001,
                    "Real imported boot vertices must clear the pitch")
                func point(_ index: Int) -> SIMD3<Float> {
                    let value = modelToWorld * candidate.pose.modelSpaceTransforms[index].columns.3
                    return [value.x, value.y, value.z]
                }
                return ToeSnapshot144(time: time, stages: current.stages, legacyStages: control.stages,
                    vertices: vertices, ankle: point(ankle), toe: point(toe),
                    transforms: candidate.model.jointTransforms)
            }

            func append(_ a: ToeSnapshot144, _ b: ToeSnapshot144, fields: [String: Any]) throws {
                let vertexSteps = zip(a.vertices, b.vertices).map { simd_distance($0, $1) }
                var row = fields
                row["detail"] = String(describing: detail)
                row["previousTime"] = a.time; row["time"] = b.time
                row["before"] = metadata(context, time: a.time); row["after"] = metadata(context, time: b.time)
                row["beforeGaitPhase"] = context.player.gaitPhase(at: a.time)
                row["afterGaitPhase"] = context.player.gaitPhase(at: b.time)
                row["bootVertexCountsLeftRight"] = boots.counts
                row["toeWeightedVertexCountsLeftRight"] = boots.toeCounts
                row["maximumBootVertexStepMetres"] = vertexSteps.max()!
                row["rightBootVertexStepMetres"] = vertexSteps[boots.counts[0]...].max()!
                row["minimumBootClearanceMetres"] = min(a.vertices.map(\.y).min()!, b.vertices.map(\.y).min()!)
                row["rightAnkleWorldStepMetres"] = simd_distance(a.ankle, b.ankle)
                row["rightToePivotWorldStepMetres"] = simd_distance(a.toe, b.toe)
                row["stages"] = try Stage.allCases.map { stage -> [String: Any] in
                    let before = try XCTUnwrap(a.stages[stage]), after = try XCTUnwrap(b.stages[stage])
                    let oldBefore = try XCTUnwrap(a.legacyStages[stage]), oldAfter = try XCTUnwrap(b.legacyStages[stage])
                    XCTAssertEqual(after.rotations[toe], try XCTUnwrap(b.stages[.source]).rotations[toe],
                        "This unplanted header must leave source toe flexion unchanged at every stage")
                    return ["stage": stage.rawValue,
                        "rightToeStepDegrees": toeAngle144(before.rotations[toe], after.rotations[toe]),
                        "rightAnkleStepDegrees": toeAngle144(before.rotations[ankle], after.rotations[ankle]),
                        "legacyRightToeStepDegrees": toeAngle144(oldBefore.rotations[toe], oldAfter.rotations[toe]),
                        "rightToeSourceDifferenceDegrees": toeAngle144(after.rotations[toe],
                            try XCTUnwrap(b.stages[.source]).rotations[toe])]
                }
                rows.append(row)
            }

            let intervals: [(String, Double, Double, Double)] = [
                ("entry", 466.0 / 120, 467.0 / 120, context.header.startTime),
                ("exit", 567.0 / 120, 568.0 / 120, context.header.endTime)
            ]
            for (edge, first, last, cueBoundary) in intervals {
                var coarseToe: Float = 0, coarseBoot: Float = 0
                for divisions in [1, 8, 64] {
                    var previous = try snapshot(first)
                    var maximumToe: Float = 0, maximumBoot: Float = 0
                    for index in 1...divisions {
                        let next = try snapshot(first + (last - first) * Double(index) / Double(divisions))
                        let before = try XCTUnwrap(previous.stages[.finalFloor])
                        let after = try XCTUnwrap(next.stages[.finalFloor])
                        maximumToe = max(maximumToe, toeAngle144(before.rotations[toe], after.rotations[toe]))
                        maximumBoot = max(maximumBoot,
                            zip(previous.vertices, next.vertices).map { simd_distance($0, $1) }.max()!)
                        try append(previous, next, fields: ["kind": "peakSubdivision", "edge": edge,
                            "divisions": divisions, "subdivisionIndex": index])
                        previous = next
                    }
                    if divisions == 1 {
                        coarseToe = maximumToe; coarseBoot = maximumBoot
                        XCTAssertGreaterThan(coarseToe, 7, "Reproduce the originally measured source peak")
                    } else {
                        // A retained jump would stay large as dt shrinks.
                        // Allow twice linear scaling, plus Float roundoff.
                        XCTAssertLessThan(maximumToe, coarseToe * 2 / Float(divisions) + 0.001)
                        XCTAssertLessThan(maximumBoot, coarseBoot * 2 / Float(divisions) + 0.000_01)
                    }
                }
                let middle = (first + last) / 2
                let cycle = floor(Double(context.player.gaitPhase(at: middle)) / (2 * .pi))
                let sourceTime = (Double(context.player.gaitPhase(at: middle)) / (2 * .pi) - cycle)
                    * run.durationSeconds
                let upper = try XCTUnwrap(run.frames.firstIndex { $0.time > sourceTime })
                XCTAssertGreaterThan(upper, 0)
                var boundaries: [(String, Double)] = [("peakMidpoint", middle), ("cueBoundary", cueBoundary)]
                for index in [upper - 1, upper] {
                    let targetPhase = (cycle + run.frames[index].time / run.durationSeconds) * (2 * .pi)
                    var lowerTime = first - 0.1, upperTime = last + 0.1
                    XCTAssertLessThan(Double(context.player.gaitPhase(at: lowerTime)), targetPhase)
                    XCTAssertGreaterThan(Double(context.player.gaitPhase(at: upperTime)), targetPhase)
                    // Locate the exact Float gait-phase crossing used by the
                    // source sampler, rather than round to a display frame.
                    for _ in 0..<48 {
                        let time = (lowerTime + upperTime) / 2
                        if Double(context.player.gaitPhase(at: time)) < targetPhase { lowerTime = time }
                        else { upperTime = time }
                    }
                    boundaries.append(("runFrame\(index)", (lowerTime + upperTime) / 2))
                }
                boundaries += context.player.keyframes.filter { abs($0.time - middle) < 0.05 }
                    .map { ("trackKeyframe", $0.time) }
                for (kind, boundary) in boundaries {
                    var referenceToe: Float = 0, referenceBoot: Float = 0
                    for epsilon in [1.0 / 120, 0.001, 0.0001, 0.00001] {
                        let before = try snapshot(boundary - epsilon), after = try snapshot(boundary + epsilon)
                        let a = try XCTUnwrap(before.stages[.finalFloor]), b = try XCTUnwrap(after.stages[.finalFloor])
                        let toeDelta = toeAngle144(a.rotations[toe], b.rotations[toe])
                        let bootDelta = zip(before.vertices, after.vertices).map { simd_distance($0, $1) }.max()!
                        if epsilon == 0.001 { referenceToe = toeDelta; referenceBoot = bootDelta }
                        if epsilon == 0.00001 {
                            XCTAssertLessThan(toeDelta, referenceToe * 0.05 + 0.001,
                                "Toe motion must shrink when approaching \(kind), not retain a finite jump")
                            XCTAssertLessThan(bootDelta, referenceBoot * 0.05 + 0.000_01,
                                "Actual boot motion must also converge at \(kind)")
                        }
                        try append(before, after, fields: ["kind": "boundaryLimit", "edge": edge,
                            "boundaryKind": kind, "boundaryTime": boundary, "epsilonSeconds": epsilon,
                            "sourceSpanLowerFrame": upper - 1, "sourceSpanUpperFrame": upper,
                            "sourceClipTimeAtPeakMidpoint": sourceTime])
                        let rewind = try snapshot(boundary - epsilon)
                        XCTAssertEqual(rewind.transforms, before.transforms)
                        XCTAssertEqual(rewind.vertices, before.vertices)
                    }
                }
            }
        }
        rows.append(["scope": "Two measured City native toe intervals, source/track/cue convergence, and CPU linear-blend deformation of actual imported near/low boot vertices; no GPU readback or comfort claim. Relative convergence assertions distinguish fast continuous motion from a retained jump; no production motion change."])
        try attach(rows, name: "ToeSourceAndBootMotion144")
    }

    private struct ToeTimeline144: Decodable {
        struct Clip: Decodable {
            struct Frame: Decodable { let time: Double }
            let id: String
            let durationSeconds: Double
            let frames: [Frame]
        }
        let clips: [Clip]
    }

    private struct ToeSnapshot144 {
        let time: Double
        let stages: [Stage: ReplaySkinnedAthleteMotion.Pose]
        let legacyStages: [Stage: ReplaySkinnedAthleteMotion.Pose]
        let vertices: [SIMD3<Float>]
        let ankle: SIMD3<Float>
        let toe: SIMD3<Float>
        let transforms: [Transform]
    }

    /// Test-owned LBS uses the imported mesh's actual inverse binds and weights.
    /// Only vertices wholly owned by an ankle/toe chain below the rest ankle
    /// enter the boot set; each side must include nonzero toe-weighted vertices.
    private struct ToeBootSurface144 {
        private struct Influence {
            let joint: Int
            let point: SIMD4<Float>
            let weight: Float
        }
        private let vertices: [[Influence]]
        let counts: [Int]
        let toeCounts: [Int]

        init(skin: ReplaySkinnedAthleteInstance) throws {
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            XCTAssertEqual(skeleton.joints.map(\.name), skin.motion.jointNames)
            var result: [[Influence]] = [], counts: [Int] = [], toeCounts: [Int] = []
            for side in ["left", "right"] {
                let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Ankle"])
                let toe = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Toe"])
                let allowed = Set(skin.motion.joints.indices.filter { index in
                    var cursor = index
                    while cursor >= 0 {
                        if cursor == ankle { return true }
                        cursor = skin.motion.joints[cursor].parentIndex
                    }
                    return false
                })
                let initialCount = result.count
                var toeCount = 0
                for part in contents.models.flatMap({ Array($0.parts) }) {
                    let weights = try XCTUnwrap(part.jointInfluences).influences.elements
                    guard !part.positions.elements.isEmpty,
                          weights.count.isMultiple(of: part.positions.count) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let count = weights.count / part.positions.count
                    guard (1...8).contains(count) else { throw CocoaError(.fileReadCorruptFile) }
                    for (index, position) in part.positions.elements.enumerated() {
                        let slice = weights[(index * count)..<((index + 1) * count)].filter { $0.weight > 0 }
                        guard !slice.isEmpty, slice.allSatisfy({ allowed.contains($0.jointIndex) }) else { continue }
                        let influences = slice.map { influence in
                            Influence(joint: influence.jointIndex,
                                point: skeleton.joints[influence.jointIndex].inverseBindPoseMatrix * SIMD4(position, 1),
                                weight: influence.weight)
                        }
                        let rest = influences.reduce(SIMD4<Float>.zero) {
                            $0 + skin.motion.restPose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                        }
                        guard rest.y < skin.motion.restPose.modelSpaceTransforms[ankle].columns.3.y + 0.04 else { continue }
                        XCTAssertEqual(rest.w, 1, accuracy: 0.000_01)
                        result.append(influences)
                        if slice.contains(where: { $0.jointIndex == toe && $0.weight > 0.001 }) { toeCount += 1 }
                    }
                }
                counts.append(result.count - initialCount); toeCounts.append(toeCount)
                XCTAssertGreaterThan(result.count - initialCount, 10)
                XCTAssertGreaterThan(toeCount, 0)
                guard result.count > initialCount else { throw CocoaError(.fileReadCorruptFile) }
            }
            vertices = result; self.counts = counts; self.toeCounts = toeCounts
        }

        func positions(in pose: ReplaySkinnedAthleteMotion.Pose, modelToWorld: simd_float4x4) -> [SIMD3<Float>] {
            vertices.map { influences in
                let local = influences.reduce(SIMD4<Float>.zero) {
                    $0 + pose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                }
                let world = modelToWorld * local
                return [world.x, world.y, world.z]
            }
        }
    }

    /// Double relative-quaternion atan2 stays useful below the Float acos floor.
    private func toeAngle144(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        func precise(_ q: simd_quatf) -> simd_quatd {
            simd_normalize(simd_quatd(ix: Double(q.imag.x), iy: Double(q.imag.y),
                                      iz: Double(q.imag.z), r: Double(q.real)))
        }
        let delta = precise(a).inverse * precise(b)
        return Float(2 * atan2(simd_length(delta.imag), abs(delta.real)) * 180 / .pi)
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
