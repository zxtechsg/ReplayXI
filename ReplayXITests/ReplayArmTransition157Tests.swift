import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Native attribution, not a motion-quality acceptance threshold. No clip,
/// route, contact, or animation policy is changed by this diagnostic.
@MainActor
final class ReplayArmTransition157Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage
    private typealias Pose = ReplaySkinnedAthleteMotion.Pose

    private final class Capture {
        var stages: [Stage: Pose] = [:]
        var authored: ReplayAthleteLocomotionPose?
        var phaseWeight: Float = 0
        var influence: Float = 0

        func reset() {
            stages.removeAll(keepingCapacity: true)
            authored = nil
            phaseWeight = 0
            influence = 0
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

    private struct Frame {
        let time: Double
        let stages: [Stage: Pose]
        let target: Pose?
        let published: [Transform]
        let modelToPitch: simd_float4x4
        let metadata: [String: Any]
    }

    private struct Peak {
        let degrees: Float
        let joint: Int
        let before: Frame
        let after: Frame
    }

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func makeContext() async throws -> Context {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let track = try XCTUnwrap(scenario.player(id: "arg-10"))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.missedTouchCount, 0)
        let cues = try recording.touches.filter { $0.playerID == track.id }.map {
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        return .init(scenario: scenario, track: track, recording: recording, cues: cues)
    }

    private func observe(_ skin: ReplaySkinnedAthleteInstance, capture: Capture) {
        skin.poseStageObserverForTesting = { stage, pose in capture.stages[stage] = pose }
        skin.authoredPoseObserverForTesting = { authored, phase, influence in
            capture.authored = authored
            capture.phaseWeight = phase
            capture.influence = influence
        }
    }

    private func sample(_ skin: ReplaySkinnedAthleteInstance, capture: Capture,
                        context: Context, at time: Double) throws -> Frame {
        capture.reset()
        let track = context.track
        let presentation = track.presentationPose(at: time)
        let locomotion = track.locomotion(at: time)
        let cue = context.cue(at: time)
        let ballBefore = context.recording.sample(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let look = ReplayAthleteTacticalAttention.target(for: track, at: time, pose: presentation,
            ball: context.recording.sample(at: time).position, players: context.scenario.players,
            poses: poses, contacts: context.cues)
        let callsBefore = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
        XCTAssertTrue(skin.update(at: time, track: track, locomotion: locomotion, lookTarget: look,
            ballAction: nil, interaction: cue, presentationPose: presentation,
            allowsTrackLocomotionSampling: true))
        let actualCalls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - callsBefore
        XCTAssertTrue(actualCalls == 0 || actualCalls == 2)
        XCTAssertEqual(Set(capture.stages.keys), Set(Stage.allCases))
        let ballAfter = context.recording.sample(at: time)
        XCTAssertEqual(ballAfter.position, ballBefore.position)
        XCTAssertEqual(ballAfter.orientation, ballBefore.orientation)
        XCTAssertEqual(ballAfter.velocity, ballBefore.velocity)
        XCTAssertEqual(ballAfter.angularVelocity, ballBefore.angularVelocity)
        var independentSource = skin.motion.makePoseBuffer()
        let effort = locomotion.effort * min(max(locomotion.speedMetresPerSecond / 2.4, 0), 1)
        skin.motion.sample(time: time, locomotionEffort: effort,
                           gaitPhase: track.gaitPhase(at: time), into: &independentSource)
        let capturedSource = try XCTUnwrap(capture.stages[.source])
        XCTAssertEqual(capturedSource.rotations, independentSource.rotations)
        XCTAssertEqual(capturedSource.translations, independentSource.translations)
        XCTAssertEqual(capturedSource.scales, independentSource.scales)

        // This second scalar call is diagnostic work, not included in the
        // actual provider-call count above. It never affects animation state.
        let cut = ReplaySkinnedAthleteCutWeight.sample(source: skin.motion.sourceCommit,
            track: track, at: time, locomotion: locomotion, interaction: cue,
            enabled: !skin.disablesCutWeightSmoothingForTesting)
        let action = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: track,
            presentationPose: presentation)
        let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
            presentationPose: presentation, lookTarget: look, interaction: cue)
        let armWeight = max(cut.influence, action?.influence ?? 0, movement?.readiness ?? 0)
        let protection = ReplayAthleteMovementIntent.contactProtection(for: cue, track: track, at: time)
        if protection >= 1 { XCTAssertEqual(actualCalls, 0) }

        var stages: [Stage: Pose] = [:]
        for stage in Stage.allCases {
            var pose = try XCTUnwrap(capture.stages[stage])
            // The source sampler deliberately leaves hierarchy matrices stale.
            // Rebuild only a captured value, never the live provider's pose.
            skin.motion.rebuildModelSpaceTransforms(in: &pose)
            stages[stage] = pose
            try assertBoneLengths(pose, motion: skin.motion)
        }
        let final = try XCTUnwrap(stages[.finalFloor])
        let cervical = try XCTUnwrap(stages[.cervical])
        XCTAssertEqual(final.rotations, cervical.rotations)
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: final) - skin.motion.geometry.restMinY,
                                    skin.contactSurface.paddingMetres - 0.0001)

        var fullTarget: Pose?
        if let authored = capture.authored {
            var partial = try XCTUnwrap(capture.stages[.source])
            var retarget = try XCTUnwrap(ReplaySkinnedAthleteFootballPose(motion: skin.motion,
                                                                        bootMarkers: skin.bootMarkers))
            retarget.apply(authored, influence: capture.influence, armInfluence: armWeight,
                           motion: skin.motion, to: &partial, interaction: action)
            let native = try XCTUnwrap(capture.stages[.footballRetargetAndContact])
            // Exact parity is required before attributing anything to the
            // full-weight target recovered with this same public/internal API.
            XCTAssertEqual(partial.rotations, native.rotations)
            XCTAssertEqual(partial.translations, native.translations)
            XCTAssertEqual(partial.scales, native.scales)
            var target = try XCTUnwrap(capture.stages[.source])
            retarget.apply(authored, influence: 1, armInfluence: 1,
                           motion: skin.motion, to: &target, interaction: action)
            skin.motion.rebuildModelSpaceTransforms(in: &target)
            fullTarget = target
        }
        let placement = Transform(rotation: simd_quatf(angle: presentation.facingDegrees * .pi / 180,
                                                      axis: [0, 1, 0]),
                                  translation: [presentation.position.x, 0, presentation.position.z]).matrix
        let modelToPitch = placement * skin.root.transform.matrix * skin.model.transformMatrix(relativeTo: skin.root)
        var metadata: [String: Any] = [
            "time": time, "speedMetresPerSecond": locomotion.speedMetresPerSecond,
            "turnDegreesPerSecond": locomotion.turnRateDegreesPerSecond,
            "gaitPhaseRadians": track.gaitPhase(at: time), "phaseAlignmentWeight": capture.phaseWeight,
            "rawCutWeight": cut.rawInfluence, "filteredCutWeight": cut.influence,
            "cutFilterAdmission": cut.admission, "retargetWeight": capture.influence,
            "armWeight": armWeight, "movementInfluence": movement?.influence ?? 0,
            "readiness": movement?.readiness ?? 0, "contactProtection": protection,
            "actionInfluence": action?.influence ?? 0, "actualProviderNeighbourSamples": actualCalls,
            "fullTargetAvailable": fullTarget != nil, "minimumFinalSkinFloorMetres":
                skin.contactSurface.minimumY(in: final) - skin.motion.geometry.restMinY
        ]
        if let cue {
            metadata["cueKind"] = cue.kind.rawValue
            metadata["cueContactTime"] = cue.contactTime
            metadata["cueStartTime"] = cue.startTime
            metadata["cueEndTime"] = cue.endTime
        }
        if let authored = capture.authored {
            metadata["authoredArmsLocalQuaternions"] = [
                "leftShoulder": vector(authored.leftShoulderOrientation.vector),
                "leftElbow": vector(authored.leftElbowOrientation.vector),
                "leftWrist": vector(authored.leftWristOrientation.vector),
                "rightShoulder": vector(authored.rightShoulderOrientation.vector),
                "rightElbow": vector(authored.rightElbowOrientation.vector),
                "rightWrist": vector(authored.rightWristOrientation.vector)
            ]
        }
        return .init(time: time, stages: stages, target: fullTarget, published: skin.model.jointTransforms,
                     modelToPitch: modelToPitch, metadata: metadata)
    }

    func testActualReboundArmNativeStagesAndShrinkingEpsilonNearLow() async throws {
        let context = try await makeContext()
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var receipt: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let capture = Capture()
            observe(skin, capture: capture)
            defer { skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil }
            let armIndices = try indices(skin.motion)
            // Global 120 Hz ticks retain the known 1.816667 -> 1.825 s pair.
            var times: [Double] = [1.76]
            for tick in 212...225 { times.append(Double(tick) / 120) }
            times.append(1.88)
            var frames: [Frame] = []
            for time in times {
                frames.append(try sample(skin, capture: capture, context: context, at: time))
            }
            var peaks: [Stage: Peak] = [:]
            for stage in Stage.allCases {
                for pair in zip(frames, frames.dropFirst()) where abs(pair.1.time - pair.0.time - 1.0 / 120) < 1e-9 {
                    let before = try XCTUnwrap(pair.0.stages[stage])
                    let after = try XCTUnwrap(pair.1.stages[stage])
                    for joint in armIndices {
                        let degrees = angle(before.rotations[joint], after.rotations[joint])
                        if peaks[stage] == nil || degrees > peaks[stage]!.degrees {
                            peaks[stage] = .init(degrees: degrees, joint: joint, before: pair.0, after: pair.1)
                        }
                    }
                }
            }
            let peak = try XCTUnwrap(peaks[.finalFloor])
            XCTAssertGreaterThan(peak.degrees, 0.1, "This diagnostic must exercise a moving arm")
            let nativeRows = frames.map { frameRow($0, motion: skin.motion, joints: armIndices) }
            var peakRows: [[String: Any]] = []
            for stage in Stage.allCases {
                let value = try XCTUnwrap(peaks[stage])
                var row = try deltaRow(value.before, value.after, motion: skin.motion, joints: armIndices)
                row["peakStage"] = stage.rawValue
                row["peakJoint"] = value.joint
                row["peakName"] = skin.motion.joints[value.joint].name
                row["peakLocalDegrees"] = value.degrees
                peakRows.append(row)
            }

            // Narrow the maximum transition in the native peak's own interval.
            // For a steep continuous motion these differences shrink; a branch
            // jump survives. This is a diagnostic, not a claim that either won.
            var lower = peak.before
            var upper = peak.after
            var narrowed: [[String: Any]] = []
            for iteration in 0..<18 {
                let middle = try sample(skin, capture: capture, context: context, at: (lower.time + upper.time) / 2)
                let lowPose = try XCTUnwrap(lower.stages[.finalFloor])
                let midPose = try XCTUnwrap(middle.stages[.finalFloor])
                let highPose = try XCTUnwrap(upper.stages[.finalFloor])
                let left = angle(lowPose.rotations[peak.joint], midPose.rotations[peak.joint])
                let right = angle(midPose.rotations[peak.joint], highPose.rotations[peak.joint])
                if left >= right { upper = middle } else { lower = middle }
                var row = try deltaRow(lower, upper, motion: skin.motion, joints: armIndices)
                row["iteration"] = iteration
                narrowed.append(row)
            }
            let centre = (lower.time + upper.time) / 2
            var epsilonRows: [[String: Any]] = []
            for (label, time) in [("nativePeakTimestamp", peak.after.time), ("narrowedFinalMaximum", centre)] {
                for epsilon in [1.0 / 240, 0.001, 0.0001, 0.00001, 0.000001] {
                    let before = try sample(skin, capture: capture, context: context, at: time - epsilon)
                    let after = try sample(skin, capture: capture, context: context, at: time + epsilon)
                    var row = try deltaRow(before, after, motion: skin.motion, joints: armIndices)
                    row["centreKind"] = label
                    row["centreTime"] = time
                    row["epsilonSeconds"] = epsilon
                    row["before"] = frameRow(before, motion: skin.motion, joints: armIndices)
                    row["after"] = frameRow(after, motion: skin.motion, joints: armIndices)
                    epsilonRows.append(row)
                    let rewound = try sample(skin, capture: capture, context: context, at: before.time)
                    assertExactFrame(rewound, before)
                }
            }
            for expected in frames.reversed() {
                let rewound = try sample(skin, capture: capture, context: context, at: expected.time)
                assertExactFrame(rewound, expected)
            }
            receipt.append(["scenario": context.scenario.id, "player": context.track.id,
                "detail": String(describing: detail), "nativeFrames": nativeRows,
                "nativeStagePeaks": peakRows, "narrowedPeakIntervals": narrowed,
                "shrinkingEpsilon": epsilonRows, "exactRewind": true,
                "globalTransformSpace": "Skeleton model space; pitch matrices additionally include authored route, facing, appearance scale and skin offset",
                "targetScope": "Full-weight reconstruction; actual partial retarget checked bit-exact before target measurements",
                "limit": "Authored animation attribution only; no video, force, visual-snap or quality claim"])
        }
        try attach(receipt, name: "ActualReboundArmStages")
    }

    func testRecordedArg10ContactCoresRemainExactAgainstUnsmoothedControlAndRewind() async throws {
        let context = try await makeContext()
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        XCTAssertFalse(context.cues.isEmpty)
        var receipt: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let control = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            control.disablesCutWeightSmoothingForTesting = true
            let capture = Capture(), controlCapture = Capture()
            observe(skin, capture: capture)
            observe(control, capture: controlCapture)
            defer {
                for instance in [skin, control] {
                    instance.poseStageObserverForTesting = nil
                    instance.authoredPoseObserverForTesting = nil
                }
            }
            var count = 0
            for cue in context.cues {
                for offset in [-0.1, 0, 0.1] {
                    let time = cue.contactTime + offset
                    let active = try XCTUnwrap(context.cue(at: time))
                    XCTAssertEqual(active.contactTime, cue.contactTime)
                    XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: active,
                        track: context.track, at: time), 1)
                    let current = try sample(skin, capture: capture, context: context, at: time)
                    let baseline = try sample(control, capture: controlCapture, context: context, at: time)
                    assertExactFrame(current, baseline)
                    _ = try sample(skin, capture: capture, context: context, at: 1.825)
                    let rewound = try sample(skin, capture: capture, context: context, at: time)
                    assertExactFrame(rewound, current)
                    count += 1
                }
            }
            XCTAssertGreaterThan(count, 0)
            receipt.append(["detail": String(describing: detail), "protectedCoreFramesExact": count,
                            "exactRewind": true, "missedRecordedTouches": context.recording.missedTouchCount])
        }
        try attach(receipt, name: "ProtectedContactControls")
    }

    private func indices(_ motion: ReplaySkinnedAthleteMotion) throws -> [Int] {
        try ["leftShoulder", "leftElbow", "leftWrist", "rightShoulder", "rightElbow", "rightWrist"].map {
            try XCTUnwrap(motion.semanticJointIndices[$0])
        }
    }

    private func assertBoneLengths(_ pose: Pose, motion: ReplaySkinnedAthleteMotion) throws {
        for side in ["left", "right"] {
            for pair in [("Shoulder", "Elbow"), ("Elbow", "Wrist"), ("Hip", "Knee"), ("Knee", "Ankle")] {
                let a = try XCTUnwrap(motion.semanticJointIndices[side + pair.0])
                let b = try XCTUnwrap(motion.semanticJointIndices[side + pair.1])
                let length = simd_distance(pose.modelSpaceTransforms[a].columns.3, pose.modelSpaceTransforms[b].columns.3)
                let rest = simd_distance(motion.restPose.modelSpaceTransforms[a].columns.3,
                                         motion.restPose.modelSpaceTransforms[b].columns.3)
                XCTAssertEqual(length, rest, accuracy: 0.0002)
            }
        }
    }

    private func assertExactFrame(_ actual: Frame, _ expected: Frame) {
        XCTAssertEqual(actual.published, expected.published)
        for stage in Stage.allCases {
            XCTAssertEqual(actual.stages[stage]?.translations, expected.stages[stage]?.translations)
            XCTAssertEqual(actual.stages[stage]?.rotations, expected.stages[stage]?.rotations)
            XCTAssertEqual(actual.stages[stage]?.scales, expected.stages[stage]?.scales)
        }
    }

    private func frameRow(_ frame: Frame, motion: ReplaySkinnedAthleteMotion, joints: [Int]) -> [String: Any] {
        var row = frame.metadata
        row["stages"] = Stage.allCases.map { stage -> [String: Any] in
            guard let pose = frame.stages[stage] else { return ["missing": stage.rawValue] }
            let values = joints.map { index -> [String: Any] in
                let matrix = pose.modelSpaceTransforms[index]
                return ["joint": index, "name": motion.joints[index].name,
                    "localQuaternion": vector(pose.rotations[index].vector),
                    "modelGlobalQuaternion": vector(simd_normalize(simd_quatf(matrix)).vector),
                    "modelGlobalTransform": elements(matrix),
                    "pitchGlobalTransform": elements(frame.modelToPitch * matrix)]
            }
            return ["stage": stage.rawValue, "arms": values]
        }
        if let target = frame.target, let source = frame.stages[.source] {
            row["sourceTarget"] = joints.map { index -> [String: Any] in
                ["joint": index, "name": motion.joints[index].name,
                 "targetLocalQuaternion": vector(target.rotations[index].vector),
                 "targetModelGlobalTransform": elements(target.modelSpaceTransforms[index]),
                 "absoluteQuaternionDot": abs(simd_dot(source.rotations[index].vector, target.rotations[index].vector)),
                 "separationDegrees": angle(source.rotations[index], target.rotations[index])]
            }
        }
        return row
    }

    private func deltaRow(_ before: Frame, _ after: Frame, motion: ReplaySkinnedAthleteMotion,
                          joints: [Int]) throws -> [String: Any] {
        var stages: [[String: Any]] = []
        for stage in Stage.allCases {
            let a = try XCTUnwrap(before.stages[stage]), b = try XCTUnwrap(after.stages[stage])
            let values = joints.map { index -> [String: Any] in
                let ma = a.modelSpaceTransforms[index], mb = b.modelSpaceTransforms[index]
                return ["joint": index, "name": motion.joints[index].name,
                    "localDegrees": angle(a.rotations[index], b.rotations[index]),
                    "modelGlobalDegrees": angle(simd_quatf(ma), simd_quatf(mb)),
                    "modelGlobalDistanceMetres": simd_distance(ma.columns.3, mb.columns.3),
                    "pitchGlobalDistanceMetres": simd_distance((before.modelToPitch * ma).columns.3,
                                                               (after.modelToPitch * mb).columns.3)]
            }
            stages.append(["stage": stage.rawValue, "arms": values])
        }
        var row: [String: Any] = ["beforeTime": before.time, "afterTime": after.time,
            "durationSeconds": after.time - before.time, "stages": stages,
            "beforeWeights": before.metadata, "afterWeights": after.metadata]
        if let ta = before.target, let tb = after.target,
           let sa = before.stages[.source], let sb = after.stages[.source] {
            // Full-weight slerp returns the source's hemisphere. Align BOTH
            // time-adjacent quaternion gauges before testing signed dot changes;
            // otherwise a representation sign flip can mimic a 180-degree edge.
            row["targetInterval"] = joints.map { index -> [String: Any] in
                let sourceAfter = aligned(sb.rotations[index], to: sa.rotations[index])
                let targetAfter = aligned(tb.rotations[index], to: ta.rotations[index])
                return ["joint": index, "sourceLocalDegrees": angle(sa.rotations[index], sb.rotations[index]),
                    "targetLocalDegrees": angle(ta.rotations[index], tb.rotations[index]),
                    "gaugeAlignedDotBefore": simd_dot(sa.rotations[index].vector, ta.rotations[index].vector),
                    "gaugeAlignedDotAfter": simd_dot(sourceAfter.vector, targetAfter.vector)]
            }
        }
        return row
    }

    private func aligned(_ value: simd_quatf, to reference: simd_quatf) -> simd_quatf {
        simd_dot(value.vector, reference.vector) < 0 ? simd_quatf(vector: -value.vector) : value
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        // Double precision on the captured Float components avoids acos(dot)'s
        // ~0.04-degree floor masking convergence in shrinking-epsilon probes.
        let qa = simd_normalize(SIMD4<Double>(Double(a.vector.x), Double(a.vector.y),
                                             Double(a.vector.z), Double(a.vector.w)))
        var qb = simd_normalize(SIMD4<Double>(Double(b.vector.x), Double(b.vector.y),
                                             Double(b.vector.z), Double(b.vector.w)))
        if simd_dot(qa, qb) < 0 { qb = -qb }
        return Float(4 * atan2(simd_length(qa - qb), simd_length(qa + qb)) * 180 / .pi)
    }

    private func vector(_ value: SIMD4<Float>) -> [Float] { [value.x, value.y, value.z, value.w] }

    private func elements(_ value: simd_float4x4) -> [Float] {
        vector(value.columns.0) + vector(value.columns.1) + vector(value.columns.2) + vector(value.columns.3)
    }

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ArmTransition157-\(name).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
