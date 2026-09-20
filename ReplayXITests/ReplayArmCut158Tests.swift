import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Paired native experiment. Excursion/path totals describe authored motion,
/// not muscle energy, measured biomechanics, visual quality, or headset FPS.
@MainActor
final class ReplayArmCut158Tests: XCTestCase {
    private final class Capture {
        var source: ReplaySkinnedAthleteMotion.Pose?
        var phase: Float = 0
        var bodyWeight: Float = 0
        func reset() { source = nil; phase = 0; bodyWeight = 0 }
    }

    private struct Context {
        let scenario: ReplayScenario
        let recording: ReplayNativeBallPhysics.Recording
        let track: PlayerTrack
        let cues: [ReplayAthleteInteractionCue]

        func cue(at time: Double) -> ReplayAthleteInteractionCue? {
            cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
        }
    }

    private struct Frame {
        let time: Double
        let joints: [Transform]
        let source: ReplaySkinnedAthleteMotion.Pose
        let pose: ReplaySkinnedAthleteMotion.Pose
        let phase: Float
        let bodyWeight: Float
        let cutWeight: Float
        let suppression: Float
        let calls: Int
    }

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayArmCutTimeline.resetCountersForTesting()
        super.tearDown()
    }

    private func context(_ scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                         track: PlayerTrack) throws -> Context {
        let cues = try recording.touches.filter { $0.playerID == track.id }.map {
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        return .init(scenario: scenario, recording: recording, track: track, cues: cues)
    }

    private func rebound() async throws -> Context {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        return try context(scenario, recording: recording, track: XCTUnwrap(scenario.player(id: "arg-10")))
    }

    private func observe(_ skin: ReplaySkinnedAthleteInstance, _ capture: Capture) {
        skin.poseStageObserverForTesting = { stage, pose in
            if stage == .source { capture.source = pose }
        }
        skin.authoredPoseObserverForTesting = { _, phase, influence in
            capture.phase = phase
            capture.bodyWeight = influence
        }
    }

    private func sample(_ skin: ReplaySkinnedAthleteInstance, capture: Capture, context: Context,
                        time: Double, admission: ReplayArmCutTimeline.Admission?,
                        supplied: PlayerLocomotionSample? = nil, allowsTrackSampling: Bool = true,
                        allowsOffBall: Bool = true) throws -> Frame {
        capture.reset()
        let presentation = context.track.presentationPose(at: time)
        let locomotion = supplied ?? context.track.locomotion(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let ball = context.recording.sample(at: time)
        let look = ReplayAthleteTacticalAttention.target(for: context.track, at: time, pose: presentation,
            ball: ball.position, players: context.scenario.players, poses: poses, contacts: context.cues)
        let count = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
        XCTAssertTrue(skin.update(at: time, track: context.track, locomotion: locomotion, lookTarget: look,
            ballAction: nil, interaction: context.cue(at: time), presentationPose: presentation,
            allowsOffBallPose: allowsOffBall, allowsTrackLocomotionSampling: allowsTrackSampling,
            armCutAdmission: admission))
        let calls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount - count
        XCTAssertTrue(calls == 0 || calls == 2)
        let after = context.recording.sample(at: time)
        XCTAssertEqual(after.position, ball.position)
        XCTAssertEqual(after.velocity, ball.velocity)
        XCTAssertEqual(after.orientation, ball.orientation)
        XCTAssertEqual(after.angularVelocity, ball.angularVelocity)
        XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                    skin.contactSurface.paddingMetres - 0.0001)
        for side in ["left", "right"] {
            for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                let length = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3,
                                           skin.pose.modelSpaceTransforms[b].columns.3)
                let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3,
                                         skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                XCTAssertEqual(length, rest, accuracy: 0.0002)
            }
        }
        return .init(time: time, joints: skin.model.jointTransforms,
                     source: try XCTUnwrap(capture.source), pose: skin.pose,
                     phase: capture.phase, bodyWeight: capture.bodyWeight,
                     cutWeight: skin.armCutWeightForTesting, suppression: skin.armCutSuppressionForTesting,
                     calls: calls)
    }

    func testActualReboundPairedArmsExcursionSourceLegsContactsAndRewindNearLow() async throws {
        let context = try await rebound()
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let rows = try measure(context, start: 1.5, end: 2.3, includesContactControls: true)
        try attach(rows, name: "Rebound")
    }

    func testAllFiveBothTeamsOriginalCutPeaksNearLowAndProtectedCores() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        for scenario in FootballReferenceScenarios.all {
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                plannedTouches: FootballReferenceScenarios.touches(for: scenario))
            XCTAssertEqual(recording.missedTouchCount, 0)
            let impactID = PlayerRagdollCue.authoredDemo(for: scenario)?.playerID
            for team in FootballTeam.allCases {
                var selected: (context: Context, time: Double, delta: Float)?
                for track in scenario.players where track.team == team && !track.isGoalkeeper && track.id != impactID {
                    let context = try context(scenario, recording: recording, track: track)
                    var previousTime: Double = 0
                    var previousWeight = filteredCut(context, time: 0)
                    for index in 1...max(1, Int(scenario.duration * 30)) {
                        let time = min(Double(index) / 30, scenario.duration)
                        let weight = filteredCut(context, time: time)
                        let oldProtection = ReplayAthleteMovementIntent.contactProtection(
                            for: context.cue(at: previousTime), track: track, at: previousTime)
                        let protection = ReplayAthleteMovementIntent.contactProtection(
                            for: context.cue(at: time), track: track, at: time)
                        let delta = abs(weight - previousWeight)
                        if oldProtection == 0, protection == 0, track.locomotion(at: time).speedMetresPerSecond > 2.4,
                           selected == nil || delta > selected!.delta {
                            selected = (context, time, delta)
                        }
                        previousTime = time
                        previousWeight = weight
                    }
                }
                let chosen = try XCTUnwrap(selected, "Every actual team must contribute a tested moving track")
                let start = max(0, chosen.time - 0.4)
                let end = min(scenario.duration, chosen.time + 0.4)
                var measured = try measure(chosen.context, start: start, end: end, includesContactControls: true)
                for index in measured.indices {
                    measured[index]["selectionOriginalFilteredCutDeltaAt30Hz"] = chosen.delta
                    measured[index]["selectionTime"] = chosen.time
                }
                rows.append(contentsOf: measured)
            }
        }
        XCTAssertEqual(rows.count, FootballReferenceScenarios.all.count * FootballTeam.allCases.count * 2)
        try attach(rows, name: "FiveDemoBothTeams")
    }

    private func measure(_ context: Context, start: Double, end: Double,
                         includesContactControls: Bool) throws -> [[String: Any]] {
        let timeline = try XCTUnwrap(ReplayArmCutTimeline(track: context.track, interactions: context.cues,
                                                        duration: context.scenario.duration))
        var times: [Double] = [start]
        let first = Int(ceil(start * 120)), last = Int(floor(end * 120))
        if first <= last {
            for tick in first...last {
                let time = Double(tick) / 120
                if time > start, time < end { times.append(time) }
            }
        }
        times.append(end)
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let candidate = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            let baseline = try ReplaySkinnedAthleteProvider.make(for: context.track, detail: detail)
            baseline.disablesArmCutSmoothingForTesting = true
            let cc = Capture(), bc = Capture()
            observe(candidate, cc)
            observe(baseline, bc)
            defer {
                for skin in [candidate, baseline] {
                    skin.poseStageObserverForTesting = nil
                    skin.authoredPoseObserverForTesting = nil
                }
            }
            let armIndices = try armIndices(candidate.motion)
            let ignored = Set(armIndices)
            var current: [Frame] = [], old: [Frame] = []
            let coldCount = ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting
            var protected = 0
            for time in times {
                let locomotion = context.track.locomotion(at: time)
                let admission = try XCTUnwrap(timeline.admission(at: time, locomotion: locomotion))
                let c = try sample(candidate, capture: cc, context: context, time: time, admission: admission)
                let b = try sample(baseline, capture: bc, context: context, time: time, admission: admission)
                assertUnchangedNonArms(c, b, ignoring: ignored)
                XCTAssertGreaterThanOrEqual(c.cutWeight, 0)
                XCTAssertLessThanOrEqual(c.cutWeight, b.cutWeight)
                if b.cutWeight == 0 { XCTAssertEqual(c.cutWeight, 0) }
                XCTAssertEqual(c.calls, b.calls, "No extra warm locomotion samples")
                if ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time),
                                                                 track: context.track, at: time) >= 1 {
                    XCTAssertEqual(c.joints, b.joints)
                    protected += 1
                }
                current.append(c)
                old.append(b)
            }
            for index in times.indices.reversed() {
                let time = times[index]
                let admission = try XCTUnwrap(timeline.admission(at: time, locomotion: context.track.locomotion(at: time)))
                let c = try sample(candidate, capture: cc, context: context, time: time, admission: admission)
                XCTAssertEqual(c.joints, current[index].joints)
                XCTAssertEqual(c.cutWeight, current[index].cutWeight)
                XCTAssertEqual(c.source.rotations, current[index].source.rotations)
            }
            if includesContactControls {
                for cue in context.cues {
                    for offset in [-0.1, 0, 0.1] {
                        let time = cue.contactTime + offset
                        guard time >= 0, time <= context.scenario.duration else { continue }
                        XCTAssertEqual(ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time),
                                                                                     track: context.track, at: time), 1)
                        let admission = try XCTUnwrap(timeline.admission(at: time,
                            locomotion: context.track.locomotion(at: time)))
                        let c = try sample(candidate, capture: cc, context: context, time: time, admission: admission)
                        let b = try sample(baseline, capture: bc, context: context, time: time, admission: admission)
                        XCTAssertEqual(c.joints, b.joints)
                        assertUnchangedNonArms(c, b, ignoring: [])
                        XCTAssertEqual(c.suppression, 0)
                        protected += 1
                    }
                }
            }
            XCTAssertEqual(ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting, coldCount)
            let oldMetrics = try metrics(old, motion: candidate.motion, armIndices: armIndices)
            let candidateMetrics = try metrics(current, motion: candidate.motion, armIndices: armIndices)
            let reductions = zip(current, old).map { $0.1.cutWeight - $0.0.cutWeight }
            rows.append(["scenario": context.scenario.id, "player": context.track.id,
                "team": context.track.team.rawValue, "detail": String(describing: detail),
                "start": start, "end": end, "frameCount": times.count,
                "baseline": oldMetrics, "candidate": candidateMetrics,
                "maximumCutWeightSuppression": reductions.max() ?? 0,
                "meanCutWeightSuppression": reductions.reduce(0, +) / Float(reductions.count),
                "affectedFrames": reductions.filter { $0 > 0 }.count,
                "protectedCoreFramesExact": protected, "sourceNonArmsRootAndPhaseExact": true,
                "exactRewind": true, "noExtraWarmPolicyEvaluations": true,
                "weightTrace": zip(current, old).map {
                    ["time": $0.0.time, "candidate": Double($0.0.cutWeight),
                     "baseline": Double($0.1.cutWeight)]
                },
                "scope": "Paired authored skeleton motion; excursion/path measures are not force, visual quality or FPS"])
        }
        return rows
    }

    func testTypedAdmissionRejectsStaleTimeTrackSourceSuppliedOverrideAndDisabledPaths() async throws {
        let context = try await rebound()
        try ReplaySkinnedAthleteProvider.prewarm()
        let timeline = try XCTUnwrap(ReplayArmCutTimeline(track: context.track, interactions: context.cues,
                                                        duration: context.scenario.duration))
        let time = 1.825
        let actual = context.track.locomotion(at: time)
        let admission = try XCTUnwrap(timeline.admission(at: time, locomotion: actual))
        XCTAssertNotNil(admission.matchingWeight(sourceCommit: ReplaySkinnedAthleteCutPhase.sourceCommit,
                                                 track: context.track, at: time, locomotion: actual))
        XCTAssertNil(admission.matchingWeight(sourceCommit: "different-source", track: context.track,
                                              at: time, locomotion: actual))
        let candidate = try ReplaySkinnedAthleteProvider.make(for: context.track)
        let baseline = try ReplaySkinnedAthleteProvider.make(for: context.track)
        baseline.disablesArmCutSmoothingForTesting = true
        let cc = Capture(), bc = Capture()
        observe(candidate, cc); observe(baseline, bc)
        defer {
            for skin in [candidate, baseline] {
                skin.poseStageObserverForTesting = nil; skin.authoredPoseObserverForTesting = nil
            }
        }
        let admitted = try sample(candidate, capture: cc, context: context, time: time, admission: admission)
        XCTAssertGreaterThan(admitted.suppression, 0, "The negative controls must surround an actually active candidate")
        let override = PlayerLocomotionSample(motion: actual.motion, speedMetresPerSecond: 3.6,
            accelerationMetresPerSecondSquared: 0, turnRateDegreesPerSecond: 0, state: .jog)
        var changedFrames = context.track.keyframes
        changedFrames[0] = MotionKeyframe(time: changedFrames[0].time,
            position: .init(x: changedFrames[0].position.x + 1, z: changedFrames[0].position.z),
            facingDegrees: changedFrames[0].facingDegrees)
        let changedTrack = PlayerTrack(id: context.track.id, displayName: context.track.displayName,
            role: context.track.role, shirtNumber: context.track.shirtNumber, team: context.track.team,
            isGoalkeeper: false, keyframes: changedFrames)
        let changed = Context(scenario: context.scenario, recording: context.recording,
                              track: changedTrack, cues: context.cues)
        XCTAssertNil(admission.matchingWeight(sourceCommit: ReplaySkinnedAthleteCutPhase.sourceCommit,
                                              track: changedTrack, at: time, locomotion: actual))
        let cases: [(String, Context, Double, PlayerLocomotionSample?, Bool, Bool, ReplayArmCutTimeline.Admission?)] = [
            ("nil-default", context, time, nil, true, true, nil),
            ("stale-time", context, time + 1.0 / 120, nil, true, true, admission),
            ("same-id-mutated-route", changed, time, nil, true, true, admission),
            ("supplied-straight", context, time, override, true, true, admission),
            ("track-opt-in-off", context, time, nil, false, true, admission),
            ("offball-off", context, time, nil, true, false, admission)
        ]
        for (label, sampleContext, sampleTime, supplied, optIn, offBall, token) in cases {
            let c = try sample(candidate, capture: cc, context: sampleContext, time: sampleTime,
                admission: token, supplied: supplied, allowsTrackSampling: optIn, allowsOffBall: offBall)
            let b = try sample(baseline, capture: bc, context: sampleContext, time: sampleTime,
                admission: token, supplied: supplied, allowsTrackSampling: optIn, allowsOffBall: offBall)
            XCTAssertEqual(c.joints, b.joints, label)
            XCTAssertEqual(c.suppression, 0, label)
            XCTAssertEqual(c.calls, b.calls, label)
        }
    }

    func testTimelineBoundsKnotSlopeAndWarmNoSampling() throws {
        let track = PlayerTrack(id: "bounds", displayName: "Bounds", role: "CM", shirtNumber: 8,
            team: .home, isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .zero, facingDegrees: 0),
                .init(time: 1, position: .init(x: 0, z: 5), facingDegrees: 90),
                .init(time: 2, position: .init(x: 5, z: 5), facingDegrees: 180)
            ])
        let timeline = try XCTUnwrap(ReplayArmCutTimeline(track: track, interactions: [], duration: 2))
        XCTAssertEqual(timeline.metricsForTesting.knotCount, 241)
        XCTAssertEqual(timeline.metricsForTesting.storageBytes, 241 * MemoryLayout<Float>.stride)
        let knots = timeline.knotsForTesting
        for index in 1..<knots.count {
            XCTAssertGreaterThanOrEqual(knots[index], 0)
            XCTAssertLessThanOrEqual(knots[index], 1)
            XCTAssertLessThanOrEqual(abs(Double(knots[index] - knots[index - 1])), 4 / 120.0 + 1e-7)
        }
        let cold = ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting
        let neighbours = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
        let locomotion = track.locomotion(at: 1)
        let first = try XCTUnwrap(timeline.admission(at: 1, locomotion: locomotion))
        for _ in 0..<100 {
            XCTAssertEqual(timeline.admission(at: 1, locomotion: locomotion)?.envelopeWeight, first.envelopeWeight)
        }
        XCTAssertEqual(ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting, cold)
        XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount, neighbours)
        for duration in [Double.nan, .infinity, -1, 0, ReplaySlowRunTimeline.maximumDuration.nextUp] {
            XCTAssertNil(ReplayArmCutTimeline(track: track, interactions: [], duration: duration))
        }
        for time in [Double.nan, .infinity, -0.1, 2.1] {
            XCTAssertNil(timeline.admission(at: time, locomotion: locomotion))
        }
        XCTAssertNil(ReplayArmCutTimeline(track: track, interactions: [], duration: 2, sourceCommit: "wrong"))
        let keeper = PlayerTrack(id: track.id, displayName: track.displayName, role: "GK", shirtNumber: 1,
                                 team: .home, isGoalkeeper: true, keyframes: track.keyframes)
        XCTAssertNil(ReplayArmCutTimeline(track: keeper, interactions: [], duration: 2))
    }

    private func filteredCut(_ context: Context, time: Double) -> Float {
        ReplaySkinnedAthleteCutWeight.sample(source: ReplaySkinnedAthleteCutPhase.sourceCommit,
            track: context.track, at: time, locomotion: context.track.locomotion(at: time),
            interaction: context.cue(at: time), enabled: true).influence
    }

    private func assertUnchangedNonArms(_ a: Frame, _ b: Frame, ignoring: Set<Int>) {
        XCTAssertEqual(a.source.rotations, b.source.rotations)
        XCTAssertEqual(a.source.translations, b.source.translations)
        XCTAssertEqual(a.source.scales, b.source.scales)
        XCTAssertEqual(a.phase, b.phase)
        XCTAssertEqual(a.bodyWeight, b.bodyWeight)
        let unchanged = a.joints.indices.filter { !ignoring.contains($0) }
        XCTAssertEqual(unchanged.map { a.joints[$0] }, unchanged.map { b.joints[$0] },
                       "All non-arm locals, including floor-adjusted root/chest/legs, must remain exact at \(a.time)")
    }

    private func armIndices(_ motion: ReplaySkinnedAthleteMotion) throws -> [Int] {
        try ["leftShoulder", "leftElbow", "leftWrist", "rightShoulder", "rightElbow", "rightWrist"].map {
            try XCTUnwrap(motion.semanticJointIndices[$0])
        }
    }

    private func metrics(_ frames: [Frame], motion: ReplaySkinnedAthleteMotion,
                         armIndices: [Int]) throws -> [String: Any] {
        var maximum: Float = 0, peakTime: Double = 0, peakJoint = -1
        var angularPath: Float = 0, squaredAngularRateIntegral: Double = 0
        var maximumWeightStep: Float = 0
        var handPaths: [String: Float] = [:]
        for pair in zip(frames, frames.dropFirst()) {
            let dt = pair.1.time - pair.0.time
            guard dt > 0 else { continue }
            maximumWeightStep = max(maximumWeightStep, abs(pair.1.cutWeight - pair.0.cutWeight))
            for joint in armIndices {
                let step = angle(pair.0.joints[joint].rotation, pair.1.joints[joint].rotation)
                angularPath += step
                squaredAngularRateIntegral += Double(step * step) / dt
                if abs(dt - 1.0 / 120) < 1e-9, step > maximum {
                    maximum = step; peakTime = pair.1.time; peakJoint = joint
                }
            }
            for side in ["left", "right"] {
                let wrist = try XCTUnwrap(motion.semanticJointIndices[side + "Wrist"])
                let distance = simd_distance(pair.0.pose.modelSpaceTransforms[wrist].columns.3,
                                             pair.1.pose.modelSpaceTransforms[wrist].columns.3)
                handPaths[side, default: 0] += distance
            }
        }
        var swings: [String: [Float]] = [:]
        for side in ["left", "right"] {
            let shoulder = try XCTUnwrap(motion.semanticJointIndices[side + "Shoulder"])
            let elbow = try XCTUnwrap(motion.semanticJointIndices[side + "Elbow"])
            swings[side] = frames.map { frame in
                let shoulderPosition = frame.pose.modelSpaceTransforms[shoulder].columns.3
                let elbowPosition = frame.pose.modelSpaceTransforms[elbow].columns.3
                let chestInverse = frame.pose.modelSpaceTransforms[motion.numberAnchors.jointIndex].inverse
                let direction = chestInverse * (elbowPosition - shoulderPosition)
                return atan2(direction.z, -direction.y) * 180 / .pi
            }
        }
        let left = try XCTUnwrap(swings["left"]), right = try XCTUnwrap(swings["right"])
        let ml = left.reduce(0, +) / Float(left.count), mr = right.reduce(0, +) / Float(right.count)
        var covariance: Float = 0, leftVariance: Float = 0, rightVariance: Float = 0
        for index in left.indices {
            let l = left[index] - ml, r = right[index] - mr
            covariance += l * r; leftVariance += l * l; rightVariance += r * r
        }
        var result: [String: Any] = ["maximumArmLocalStepAt120HzDegrees": maximum,
            "peakTime": peakTime, "peakJoint": peakJoint,
            "totalSixJointAngularPathDegrees": angularPath,
            "squaredAngularRateIntegralDegreesSquaredPerSecond": squaredAngularRateIntegral,
            "leftHandModelSpacePathMetres": handPaths["left"] ?? 0,
            "rightHandModelSpacePathMetres": handPaths["right"] ?? 0,
            "leftUpperArmChestSpaceExcursionDegrees": (left.max() ?? 0) - (left.min() ?? 0),
            "rightUpperArmChestSpaceExcursionDegrees": (right.max() ?? 0) - (right.min() ?? 0),
            "maximumAdjacentWeightStep": maximumWeightStep,
            "counterSwingScope": "Pearson correlation of chest-space upper-arm sagittal angles; not a required gait target"]
        if leftVariance > 1e-6, rightVariance > 1e-6 {
            result["bilateralUpperArmSwingCorrelation"] = covariance / sqrt(leftVariance * rightVariance)
        }
        if peakJoint >= 0 { result["peakJointName"] = motion.joints[peakJoint].name }
        return result
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let qa = simd_normalize(SIMD4<Double>(Double(a.vector.x), Double(a.vector.y), Double(a.vector.z), Double(a.vector.w)))
        var qb = simd_normalize(SIMD4<Double>(Double(b.vector.x), Double(b.vector.y), Double(b.vector.z), Double(b.vector.w)))
        if simd_dot(qa, qb) < 0 { qb = -qb }
        return Float(4 * atan2(simd_length(qa - qb), simd_length(qa + qb)) * 180 / .pi)
    }

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let value = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                  uniformTypeIdentifier: "public.json")
        value.name = "ReplayXI-ArmCut158-\(name).json"
        value.lifetime = .keepAlways
        add(value)
    }
}
