import CryptoKit
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Attribution only: authored animation stages, not measured match biomechanics.
/// The source and both native controls retain their original clocks and cues.
@MainActor
final class ReplayJointTransition139Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage

    private final class Capture {
        var stages: [Stage: ReplaySkinnedAthleteMotion.Pose] = [:]
        var authored: ReplayAthleteLocomotionPose?
        var phaseAdmission: Float = 0
        var retargetInfluence: Float = 0

        func reset() {
            stages.removeAll(keepingCapacity: true)
            authored = nil; phaseAdmission = 0; retargetInfluence = 0
        }
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

    private struct Peak {
        let angle: Float
        let time: Double
        let previousTime: Double
        let joint: Int
        let name: String
        let before: SIMD4<Float>
        let after: SIMD4<Float>
    }

    // Independent cycle138 native receipts, captured before adding stage hooks.
    private let expected: [String: (aligned: String, legacy: String)] = [
        "arg-10-near": ("bd9459833df13ab8832e4d5b1f3fab4e5d20ecda0ef776b960f4be1832ce36f3", "b929095326f8cae80bafaf3e35ae7ad8bb7ce24c806ad5ab29f912c3ffd239ef"),
        "arg-10-lowDetail": ("3e7f426c1bd044886ccdb4beb42c4594e6fba7ea8731dc019c8569d26ac628fc", "9e4358cd739bebc3183ddd5b25f3cf7895eafc04600060e76ebfaec5ffd3d666"),
        "fra-5-near": ("782d90e8a59d43f0eaf3399110071ec8126c78ab687260a1d046033390a6b3e0", "98be7ec4b8b6b7438d9b4f5aedd73b423bb839249b1fd0c243b463cff3fbd348"),
        "fra-5-lowDetail": ("ec8a007fd9f947cdb57fb561a8e1a842defce58b5497f8484c68e4e6534ad8a8", "760496404eb7e1aade43226daaa0e3bc3a379118a9b136e3c6cea227b4177700")
    ]

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func context(scenario id: String, player: String) async throws -> Context {
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

    private func observe(_ skin: ReplaySkinnedAthleteInstance, into capture: Capture) {
        skin.poseStageObserverForTesting = { stage, pose in capture.stages[stage] = pose }
        skin.authoredPoseObserverForTesting = { pose, admission, influence in
            capture.authored = pose; capture.phaseAdmission = admission; capture.retargetInfluence = influence
        }
    }

    func testArg10NativeJointStageBaselineContactCoreAndExactRewind() async throws {
        let context = try await context(scenario: "final-108-rebound-v2", player: "arg-10")
        try measure(context, start: 1.20, end: 1.65)
    }

    func testFra5NativeJointStageBaselineBothControlsAndExactRewind() async throws {
        let context = try await context(scenario: "final-36-counter-v2", player: "fra-5")
        // Keep bit-identical times to the independent cycle138 worst-window scan.
        let centre = Double(338) / 30
        try measure(context, start: centre - 0.075, end: centre + 0.075)
    }

    func testSuppliedLocomotionRemainsAuthoritativeAndTrackSamplingRequiresOptIn() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let context = try await context(scenario: "final-108-rebound-v2", player: "arg-10")
        let track = context.track, time = 1.4
        let actual = track.locomotion(at: time)
        XCTAssertEqual(ReplaySkinnedAthleteFootballPose.influence(locomotion: actual, ballAction: nil), 0)
        let supplied = PlayerLocomotionSample(motion: actual.motion, speedMetresPerSecond: 3.6,
            accelerationMetresPerSecondSquared: 0, turnRateDegreesPerSecond: 0, state: .jog)
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let candidate = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            let control = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            control.disablesCutWeightSmoothingForTesting = true
            let before = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
            XCTAssertTrue(candidate.update(at: time, track: track, locomotion: supplied,
                lookTarget: nil, ballAction: nil))
            XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount, before)
            XCTAssertTrue(control.update(at: time, track: track, locomotion: supplied,
                lookTarget: nil, ballAction: nil, allowsTrackLocomotionSampling: true))
            XCTAssertEqual(candidate.model.jointTransforms, control.model.jointTransforms,
                "A supplied override must retain the exact pre-smoother output")
            var source = candidate.motion.makePoseBuffer()
            candidate.motion.sample(time: time, locomotionEffort: supplied.effort,
                gaitPhase: track.gaitPhase(at: time), into: &source)
            for side in ["left", "right"] {
                for joint in ["Shoulder", "Elbow", "Wrist"] {
                    let index = try XCTUnwrap(candidate.motion.semanticJointIndices[side + joint])
                    XCTAssertEqual(candidate.pose.rotations[index].vector, source.rotations[index].vector)
                    XCTAssertEqual(candidate.pose.translations[index], source.translations[index])
                }
            }
            // Identical real inputs differ only by the explicit contract. A
            // raw-zero track frame still admits its continuous neighbours.
            XCTAssertTrue(candidate.update(at: time, track: track, locomotion: actual,
                lookTarget: nil, ballAction: nil))
            let suppliedOnly = candidate.model.jointTransforms
            XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount, before)
            XCTAssertTrue(candidate.update(at: time, track: track, locomotion: actual,
                lookTarget: nil, ballAction: nil, allowsTrackLocomotionSampling: true))
            XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - before, 2)
            XCTAssertNotEqual(candidate.model.jointTransforms, suppliedOnly,
                "Opt-in must actually reach the native smoother on a real raw-zero frame")
        }
    }

    func testShippingSceneOptsInOnlyForTrackDerivedLocomotion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("ReplayXI/Immersive/PitchSceneFactory.swift"),
                                encoding: .utf8)
        let compact = source.components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(compact.contains("letlocomotion=stationaryPose==nil?player.locomotion(at:time):player.stationaryLocomotion"))
        let start = try XCTUnwrap(compact.range(of: "usesNewSkin=skin.update("))
        let end = try XCTUnwrap(compact.range(of: "}else{usesNewSkin=false", range: start.upperBound..<compact.endIndex))
        let shippingCall = compact[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(shippingCall.contains("locomotion:locomotion"))
        XCTAssertTrue(shippingCall.contains("allowsTrackLocomotionSampling:stationaryPose==nil"))
    }

    private func measure(_ context: Context, start: Double, end: Double) throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let track = context.track
        let times = stride(from: start, through: end + 0.00001, by: 1.0 / 120).map { $0 }
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let aligned = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            let legacy = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            legacy.disablesCutPhaseAlignmentForTesting = true
            let cycle138 = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            cycle138.disablesCutWeightSmoothingForTesting = true
            let alignedCapture = Capture(), legacyCapture = Capture(), cycle138Capture = Capture()
            observe(aligned, into: alignedCapture); observe(legacy, into: legacyCapture); observe(cycle138, into: cycle138Capture)
            defer {
                for skin in [aligned, legacy, cycle138] {
                    skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil
                }
            }
            let variants = [("aligned", aligned, alignedCapture), ("unaligned", legacy, legacyCapture),
                            ("cycle138Aligned", cycle138, cycle138Capture)]
            var previousStages: [String: [Stage: ReplaySkinnedAthleteMotion.Pose]] = [:]
            var previousAuthored: [String: [simd_quatf]] = [:]
            var saved: [String: [[Transform]]] = ["aligned": [], "unaligned": [], "cycle138Aligned": []]
            var savedStages: [String: [[Stage: [SIMD4<Float>]]]] = ["aligned": [], "unaligned": [], "cycle138Aligned": []]
            var fingerprints = ["aligned": SHA256(), "unaligned": SHA256(), "cycle138Aligned": SHA256()]
            var actualSampleCalls = ["aligned": 0, "unaligned": 0, "cycle138Aligned": 0]
            var peaks: [String: Peak] = [:]
            var protectedCoreSamples = 0
            rows.append(["jointTable": true, "detail": String(describing: detail),
                "joints": aligned.motion.joints.enumerated().map {
                    ["index": $0.offset, "name": $0.element.name, "parent": $0.element.parentIndex] as [String: Any]
                }])
            for (timeIndex, time) in times.enumerated() {
                let locomotion = track.locomotion(at: time), cue = context.cue(at: time)
                let protection = ReplayAthleteMovementIntent.contactProtection(for: cue, track: track, at: time)
                let interaction = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: track,
                    presentationPose: track.presentationPose(at: time))
                for (variant, skin, capture) in variants {
                    let callsBefore = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
                    capture.reset(); update(skin, context: context, time: time)
                    let sampleCalls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - callsBefore
                    actualSampleCalls[variant]! += sampleCalls
                    XCTAssertTrue(sampleCalls == 0 || sampleCalls == 2)
                    if variant != "aligned" || protection >= 1 { XCTAssertEqual(sampleCalls, 0) }
                    XCTAssertEqual(Set(capture.stages.keys), Set(Stage.allCases))
                    var preceding: ReplaySkinnedAthleteMotion.Pose?
                    var frameStageRotations: [Stage: [SIMD4<Float>]] = [:]
                    for stage in Stage.allCases {
                        var pose = try XCTUnwrap(capture.stages[stage])
                        // Do not alter the live provider: rebuild only this
                        // captured value copy for stage-space bone/floor data.
                        skin.motion.rebuildModelSpaceTransforms(in: &pose)
                        let previousPose = previousStages[variant]?[stage]
                        let angles = previousPose.map { prior in
                            zip(prior.rotations, pose.rotations).map { angle($0.0, $0.1) }
                        }
                        let changedHere = preceding.map { prior in
                            zip(prior.rotations, pose.rotations).map { angle($0.0, $0.1) }
                        } ?? Array(repeating: Float.zero, count: pose.rotations.count)
                        var row: [String: Any] = ["player": track.id, "detail": String(describing: detail),
                            "variant": variant, "stage": stage.rawValue, "time": time,
                            "phase": track.gaitPhase(at: time), "speed": locomotion.speedMetresPerSecond,
                            "turnRate": locomotion.turnRateDegreesPerSecond,
                            "phaseAdmission": capture.phaseAdmission, "retargetInfluence": capture.retargetInfluence,
                            "contactProtection": protection, "interactionInfluence": interaction?.influence ?? 0,
                            "actualExtraLocomotionSamples": sampleCalls,
                            "stageAddedAnglesDegrees": changedHere,
                            "localRotations": pose.rotations.map { vector($0.vector) },
                            "localTranslations": pose.translations.map { [$0.x, $0.y, $0.z] },
                            "minimumSkinFloor": skin.contactSurface.minimumY(in: pose) - skin.motion.geometry.restMinY]
                        if let angles, let index = angles.indices.max(by: { angles[$0] < angles[$1] }) {
                            row["jointStepDegrees"] = angles
                            row["peakJoint"] = index; row["peakJointName"] = skin.motion.joints[index].name
                            row["peakAngleDegrees"] = angles[index]; row["previousTime"] = times[timeIndex - 1]
                            let key = variant + "/" + stage.rawValue
                            if peaks[key] == nil || angles[index] > peaks[key]!.angle {
                                peaks[key] = Peak(angle: angles[index], time: time, previousTime: times[timeIndex - 1],
                                    joint: index, name: skin.motion.joints[index].name,
                                    before: previousStages[variant]![stage]!.rotations[index].vector,
                                    after: pose.rotations[index].vector)
                            }
                        }
                        // The final floor guard translates the root only. It
                        // must not be blamed for a quaternion jump elsewhere.
                        if stage == .finalFloor, let preceding {
                            XCTAssertEqual(pose.rotations, preceding.rotations)
                            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: pose)
                                - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                        }
                        for side in ["left", "right"] {
                            for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                                let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                                let length = simd_distance(pose.modelSpaceTransforms[a].columns.3, pose.modelSpaceTransforms[b].columns.3)
                                let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                                XCTAssertEqual(length, rest, accuracy: 0.0002)
                            }
                        }
                        frameStageRotations[stage] = pose.rotations.map(\.vector)
                        rows.append(row); preceding = pose
                    }
                    if let authored = capture.authored {
                        let rotations = authoredJoints(authored)
                        var row: [String: Any] = ["player": track.id, "detail": String(describing: detail),
                            "variant": variant, "stage": "authoredProceduralTarget", "time": time,
                            "coordinateSpace": "Procedural parent-local, not native joint indices",
                            "jointNames": authoredNames, "localRotations": rotations.map { vector($0.vector) },
                            "phaseAdmission": capture.phaseAdmission, "retargetInfluence": capture.retargetInfluence]
                        if let previous = previousAuthored[variant] {
                            row["jointStepDegrees"] = zip(previous, rotations).map { angle($0.0, $0.1) }
                        }
                        rows.append(row); previousAuthored[variant] = rotations
                    } else { previousAuthored[variant] = nil }
                    if let prior = saved[variant]?.last {
                        let angles = zip(prior, skin.model.jointTransforms).map { angle($0.0.rotation, $0.1.rotation) }
                        let index = try XCTUnwrap(angles.indices.max(by: { angles[$0] < angles[$1] }))
                        let key = variant + "/publishedModel"
                        if peaks[key] == nil || angles[index] > peaks[key]!.angle {
                            peaks[key] = Peak(angle: angles[index], time: time, previousTime: times[timeIndex - 1],
                                joint: index, name: skin.motion.joints[index].name,
                                before: prior[index].rotation.vector, after: skin.model.jointTransforms[index].rotation.vector)
                        }
                    }
                    saved[variant]!.append(skin.model.jointTransforms)
                    savedStages[variant]!.append(frameStageRotations)
                    previousStages[variant] = capture.stages
                    feed(skin.model.jointTransforms, into: &fingerprints[variant]!)
                }
                if protection >= 1 {
                    protectedCoreSamples += 1
                    XCTAssertEqual(aligned.model.jointTransforms, legacy.model.jointTransforms)
                    XCTAssertEqual(aligned.model.jointTransforms, cycle138.model.jointTransforms)
                    for stage in Stage.allCases {
                        XCTAssertEqual(alignedCapture.stages[stage]!.rotations, legacyCapture.stages[stage]!.rotations)
                        XCTAssertEqual(alignedCapture.stages[stage]!.translations, legacyCapture.stages[stage]!.translations)
                    }
                }
            }
            for (variant, skin, capture) in variants {
                for index in times.indices.reversed() {
                    capture.reset(); update(skin, context: context, time: times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[variant]![index])
                    for stage in Stage.allCases {
                        XCTAssertEqual(capture.stages[stage]!.rotations.map(\.vector), savedStages[variant]![index][stage]!)
                    }
                }
                let hash = fingerprints[variant]!.finalize().map { String(format: "%02x", $0) }.joined()
                let baseline = try XCTUnwrap(expected[track.id + "-" + String(describing: detail)])
                if variant != "aligned" {
                    XCTAssertEqual(hash, variant == "cycle138Aligned" ? baseline.aligned : baseline.legacy,
                        "Independent cycle138 controls must remain byte-exact")
                }
                rows.append(["summary": true, "player": track.id, "detail": String(describing: detail),
                    "variant": variant, "poseSHA256": hash, "protectedCoreSamples": protectedCoreSamples,
                    "actualExtraLocomotionSamplesForwardPass": actualSampleCalls[variant]!,
                    "exactStageAndFinalRewind": true])
            }
            let candidatePeak = try XCTUnwrap(peaks["aligned/publishedModel"])
            let controlPeak = try XCTUnwrap(peaks["cycle138Aligned/publishedModel"])
            XCTAssertLessThan(candidatePeak.angle, controlPeak.angle,
                "Cut smoothing must reduce the native window peak, not just a scalar weight: \(track.id)")
            if track.id == "arg-10" { XCTAssertGreaterThan(protectedCoreSamples, 0) }
            for (key, peak) in peaks.sorted(by: { $0.key < $1.key }) {
                rows.append(["peakSummary": true, "player": track.id, "detail": String(describing: detail),
                    "variantAndStage": key, "joint": peak.joint, "jointName": peak.name,
                    "time": peak.time, "previousTime": peak.previousTime, "angleDegrees": peak.angle,
                    "beforeRotation": vector(peak.before), "afterRotation": vector(peak.after)])
            }
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-JointTransition139-\(track.id).json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    func testCutWeightRawZeroEntryExitCoreAndExactReverseSampling() async throws {
        let context = try await context(scenario: "final-108-rebound-v2", player: "arg-10")
        let track = context.track
        let times = stride(from: 1.20, through: 1.65, by: 1.0 / 240).map { $0 }
        var saved: [ReplaySkinnedAthleteCutWeight.Sample] = []
        var joins = 0, fastZeroSampled = 0, core = 0
        var crossingBrackets: [(Double, Double)] = []
        var rows: [[String: Any]] = []
        for (index, time) in times.enumerated() {
            let locomotion = track.locomotion(at: time), cue = context.cue(at: time)
            let protection = ReplayAthleteMovementIntent.contactProtection(for: cue, track: track, at: time)
            let before = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
            let sample = ReplaySkinnedAthleteCutWeight.sample(source: ReplaySkinnedAthleteCutPhase.sourceCommit,
                track: track, at: time, locomotion: locomotion, interaction: cue, enabled: true)
            let calls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - before
            XCTAssertEqual(calls, sample.neighbourSamples)
            XCTAssertTrue(calls == 0 || calls == 2)
            if protection >= 1 {
                core += 1; XCTAssertEqual(sample.influence, sample.rawInfluence); XCTAssertEqual(calls, 0)
            }
            if sample.rawInfluence == 0, sample.admission > 0 {
                fastZeroSampled += 1; XCTAssertEqual(calls, 2)
            }
            if let previous = saved.last, (sample.rawInfluence == 0) != (previous.rawInfluence == 0) {
                joins += 1
                crossingBrackets.append((times[index - 1], time))
            }
            XCTAssertTrue(sample.influence.isFinite && (0...1).contains(sample.influence))
            rows.append(["time": time, "raw": sample.rawInfluence, "filtered": sample.influence,
                "admission": sample.admission, "actualExtraLocomotionSamples": calls,
                "previousFiltered": index > 0 ? saved[index - 1].influence : sample.influence])
            saved.append(sample)
        }
        XCTAssertGreaterThan(joins, 0); XCTAssertGreaterThan(fastZeroSampled, 0); XCTAssertGreaterThan(core, 0)
        for index in times.indices.reversed() {
            let sample = ReplaySkinnedAthleteCutWeight.sample(source: ReplaySkinnedAthleteCutPhase.sourceCommit,
                track: track, at: times[index], locomotion: track.locomotion(at: times[index]),
                interaction: context.cue(at: times[index]), enabled: true)
            XCTAssertEqual(sample.influence, saved[index].influence)
            XCTAssertEqual(sample.admission, saved[index].admission)
            XCTAssertEqual(sample.neighbourSamples, saved[index].neighbourSamples)
        }
        for enabled in [false, true] {
            let source = enabled ? "unknown-asset" : ReplaySkinnedAthleteCutPhase.sourceCommit
            let sample = ReplaySkinnedAthleteCutWeight.sample(source: source, track: track, at: 1.333,
                locomotion: track.locomotion(at: 1.333), interaction: nil, enabled: enabled)
            XCTAssertEqual(sample.influence, sample.rawInfluence); XCTAssertEqual(sample.neighbourSamples, 0)
        }
        try assertRawZeroBoundaryContinuity(context, brackets: crossingBrackets, rows: &rows)
        try attach(rows, name: "RawZeroAndCore")
    }

    private func assertRawZeroBoundaryContinuity(_ context: Context, brackets: [(Double, Double)],
                                                  rows: inout [[String: Any]]) throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let track = context.track
        func sample(_ time: Double) -> ReplaySkinnedAthleteCutWeight.Sample {
            ReplaySkinnedAthleteCutWeight.sample(source: ReplaySkinnedAthleteCutPhase.sourceCommit,
                track: track, at: time, locomotion: track.locomotion(at: time),
                interaction: context.cue(at: time), enabled: true)
        }
        for bracket in brackets {
            var lower = bracket.0, upper = bracket.1
            let lowerIsZero = sample(lower).rawInfluence == 0
            // A frame-sized delta mixes ordinary motion with discontinuity.
            // Locate the actual raw-zero join, then shrink the interval around
            // it. A continuous ramp converges; a raw>0 admission switch does not.
            for _ in 0..<40 {
                let middle = (lower + upper) * 0.5
                if (sample(middle).rawInfluence == 0) == lowerIsZero { lower = middle }
                else { upper = middle }
            }
            let boundary = (lower + upper) * 0.5
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                var previousScalar: Float?, previousAngle: Float?
                for epsilon in [0.001, 0.0001, 0.00001] {
                    let beforeTime = boundary - epsilon, afterTime = boundary + epsilon
                    let before = sample(beforeTime), after = sample(afterTime)
                    XCTAssertNotEqual(before.rawInfluence == 0, after.rawInfluence == 0)
                    XCTAssertEqual(before.neighbourSamples, 2); XCTAssertEqual(after.neighbourSamples, 2)
                    let scalarDelta = abs(after.influence - before.influence)
                    // Deliberately faulty negative control: omit neighbours on
                    // a raw-zero frame. Its non-vanishing jump proves this test
                    // catches the admission bug, not just smooth motion's rate.
                    let gatedBefore = before.rawInfluence == 0 ? before.rawInfluence : before.influence
                    let gatedAfter = after.rawInfluence == 0 ? after.rawInfluence : after.influence
                    let gatedDelta = abs(gatedAfter - gatedBefore)
                    XCTAssertGreaterThan(gatedDelta, 0.05)
                    update(skin, context: context, time: beforeTime)
                    let beforePose = skin.model.jointTransforms
                    update(skin, context: context, time: afterTime)
                    let afterPose = skin.model.jointTransforms
                    var maximumAngle: Float = 0, maximumTranslation: Float = 0
                    for index in beforePose.indices {
                        maximumAngle = max(maximumAngle, angle(beforePose[index].rotation, afterPose[index].rotation))
                        maximumTranslation = max(maximumTranslation,
                            simd_distance(beforePose[index].translation, afterPose[index].translation))
                    }
                    if let previousScalar, let previousAngle {
                        XCTAssertLessThan(scalarDelta, previousScalar * 0.25 + 0.00002,
                            "The scalar difference must converge as the interval shrinks")
                        // Float quaternion dot products have a ~0.06 degree
                        // noise floor even for nearly identical rotations.
                        XCTAssertLessThanOrEqual(maximumAngle, max(previousAngle * 0.4, 0.12))
                    }
                    if epsilon == 0.00001 {
                        XCTAssertLessThan(scalarDelta, 0.0005)
                        XCTAssertLessThan(maximumAngle, 0.2)
                        XCTAssertLessThan(maximumTranslation, 0.0005)
                    }
                    update(skin, context: context, time: beforeTime)
                    XCTAssertEqual(skin.model.jointTransforms, beforePose)
                    update(skin, context: context, time: afterTime)
                    XCTAssertEqual(skin.model.jointTransforms, afterPose)
                    rows.append(["boundaryContinuity": true, "boundaryTime": boundary,
                        "epsilonSeconds": epsilon, "detail": String(describing: detail),
                        "scalarDelta": scalarDelta, "deliberatelyGatedNegativeControlDelta": gatedDelta,
                        "maximumNativeJointDeltaDegrees": maximumAngle,
                        "maximumNativeLocalTranslationDeltaMetres": maximumTranslation,
                        "exactRewind": true])
                    previousScalar = scalarDelta; previousAngle = maximumAngle
                }
            }
        }
    }

    func testAllFiveBothTeamWideCutWindowsActualCostArmsFloorAndRewind() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        var fastRawZeroFrames = 0, auditedWindows = 0
        for scenario in FootballReferenceScenarios.all {
            for team in FootballTeam.allCases {
                // Select from every outfield actor, including touch owners.
                // The wide native window is chosen by the largest raw-cut
                // weight change at30Hz, not by the candidate's best result.
                var selected: (track: PlayerTrack, time: Double, score: Float)?
                for track in scenario.players where track.team == team && !track.isGoalkeeper {
                    var previous = track.locomotion(at: 0)
                    var previousWeight = ReplaySkinnedAthleteFootballPose.influence(locomotion: previous, ballAction: nil)
                    for index in 1...max(1, Int(scenario.duration * 30)) {
                        let time = min(Double(index) / 30, scenario.duration)
                        let locomotion = track.locomotion(at: time)
                        let weight = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
                        let score = abs(weight - previousWeight)
                        if max(locomotion.speedMetresPerSecond, previous.speedMetresPerSecond) > 2.4,
                           selected == nil || score > selected!.score { selected = (track, time, score) }
                        previous = locomotion; previousWeight = weight
                    }
                }
                guard let selected else {
                    rows.append(["scenario": scenario.id, "team": team.rawValue, "noFastOutfieldWindow": true])
                    continue
                }
                let context = try await context(scenario: scenario.id, player: selected.track.id)
                let start = max(0, selected.time - 0.35), end = min(scenario.duration, selected.time + 0.35)
                let times = stride(from: start, through: end + 0.00001, by: 1.0 / 120).map { $0 }
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let candidate = try ReplaySkinnedAthleteProvider.make(for: selected.track, detail: detail)
                    let control = try ReplaySkinnedAthleteProvider.make(for: selected.track, detail: detail)
                    control.disablesCutWeightSmoothingForTesting = true
                    let armIndices = Set(["left", "right"].flatMap { side in
                        ["Shoulder", "Elbow", "Wrist"].compactMap { candidate.motion.semanticJointIndices[side + $0] }
                    })
                    var saved: [[Transform]] = [], previousControl: [Transform]?
                    var maximum: Float = 0, controlMaximum: Float = 0, armMaximum: Float = 0, controlArmMaximum: Float = 0
                    var maximumTime = start, maximumJoint = 0, controlMaximumTime = start, controlMaximumJoint = 0
                    var extraSamples = 0, zeroFrames = 0, coreFrames = 0
                    for time in times {
                        let before = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
                        update(candidate, context: context, time: time)
                        let calls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - before
                        XCTAssertTrue(calls == 0 || calls == 2); extraSamples += calls
                        let controlBefore = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
                        update(control, context: context, time: time)
                        XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount, controlBefore)
                        let locomotion = selected.track.locomotion(at: time)
                        let raw = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
                        if raw == 0, calls == 2 { zeroFrames += 1 }
                        let protection = ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time),
                            track: selected.track, at: time)
                        if protection >= 1 {
                            coreFrames += 1; XCTAssertEqual(calls, 0)
                            XCTAssertEqual(candidate.model.jointTransforms, control.model.jointTransforms)
                        }
                        if let previous = saved.last, let previousControl {
                            for index in previous.indices {
                                let step = angle(previous[index].rotation, candidate.model.jointTransforms[index].rotation)
                                let oldStep = angle(previousControl[index].rotation, control.model.jointTransforms[index].rotation)
                                if step > maximum { maximum = step; maximumTime = time; maximumJoint = index }
                                if oldStep > controlMaximum { controlMaximum = oldStep; controlMaximumTime = time; controlMaximumJoint = index }
                                if armIndices.contains(index) { armMaximum = max(armMaximum, step); controlArmMaximum = max(controlArmMaximum, oldStep) }
                            }
                        }
                        for skin in [candidate, control] {
                            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                                - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                            for side in ["left", "right"] {
                                for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                                    let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                                    let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                                    let length = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3, skin.pose.modelSpaceTransforms[b].columns.3)
                                    let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                                    XCTAssertEqual(length, rest, accuracy: 0.0002)
                                }
                            }
                        }
                        saved.append(candidate.model.jointTransforms); previousControl = control.model.jointTransforms
                    }
                    for index in times.indices.reversed() {
                        update(candidate, context: context, time: times[index])
                        XCTAssertEqual(candidate.model.jointTransforms, saved[index])
                    }
                    XCTAssertLessThanOrEqual(maximum, max(10, controlMaximum + 2),
                        "Do not move the transition defect to another actor: \(scenario.id) \(selected.track.id)")
                    XCTAssertLessThanOrEqual(armMaximum, max(6, controlArmMaximum + 1),
                        "Smoothing legs must not introduce an arm snap")
                    auditedWindows += 1; fastRawZeroFrames += zeroFrames
                    rows.append(["scenario": scenario.id, "team": team.rawValue, "player": selected.track.id,
                        "detail": String(describing: detail), "start": start, "end": end,
                        "selectionRawCutStep30Hz": selected.score, "maximumJointStepDegrees": maximum,
                        "maximumJoint": maximumJoint, "maximumJointName": candidate.motion.joints[maximumJoint].name,
                        "maximumTime": maximumTime, "controlMaximumJointStepDegrees": controlMaximum,
                        "controlMaximumJoint": controlMaximumJoint, "controlMaximumTime": controlMaximumTime,
                        "maximumArmStepDegrees": armMaximum, "controlMaximumArmStepDegrees": controlArmMaximum,
                        "actualExtraLocomotionSamplesForwardPass": extraSamples, "nativeFrames": times.count,
                        "fastRawZeroFramesSampled": zeroFrames, "protectedCoreFramesExact": coreFrames,
                        "exactRewind": true])
                }
            }
        }
        XCTAssertGreaterThanOrEqual(auditedWindows, 10)
        XCTAssertGreaterThan(fastRawZeroFrames, 0)
        try attach(rows, name: "AllFiveWideWindowsAndActualCalls")
    }

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-JointTransition139-\(name).json"; receipt.lifetime = .keepAlways; add(receipt)
    }

    private var authoredNames: [String] {
        ["body", "hips", "spine", "neck", "head", "leftHip", "rightHip", "leftKnee", "rightKnee",
         "leftAnkle", "rightAnkle", "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"]
    }

    private func authoredJoints(_ p: ReplayAthleteLocomotionPose) -> [simd_quatf] {
        [p.bodyOrientation, p.hipsOrientation, p.spineOrientation, p.neckOrientation, p.headOrientation,
         p.leftHipOrientation, p.rightHipOrientation, p.leftKneeOrientation, p.rightKneeOrientation,
         p.leftAnkleOrientation, p.rightAnkleOrientation, p.leftShoulderOrientation, p.rightShoulderOrientation,
         p.leftElbowOrientation, p.rightElbowOrientation, p.leftWristOrientation, p.rightWristOrientation]
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi
    }

    private func vector(_ q: SIMD4<Float>) -> [Float] { [q.x, q.y, q.z, q.w] }

    private func feed(_ transforms: [Transform], into hash: inout SHA256) {
        for joint in transforms {
            for value in [joint.translation.x, joint.translation.y, joint.translation.z,
                joint.rotation.vector.x, joint.rotation.vector.y, joint.rotation.vector.z, joint.rotation.vector.w,
                joint.scale.x, joint.scale.y, joint.scale.z] {
                hash.update(data: Data("\(value.bitPattern),".utf8))
            }
        }
    }
}
