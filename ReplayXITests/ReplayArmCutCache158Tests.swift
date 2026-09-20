import Dispatch
import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Root-owned table integration and CPU diagnostics. No renderer or FPS claim.
@MainActor
final class ReplayArmCutCache158Tests: XCTestCase {
    private typealias Context = ReplayArmLOD147Probe.Context
    private typealias Skin = ReplaySkinnedAthleteInstance
    private struct State: Equatable {
        let graph: [String]
        let actors: [String: Transform]
        let ball: Transform
        let joints: [String: [Transform]]
    }
    private struct Input {
        let time: Double
        let locomotion: PlayerLocomotionSample
        let presentation: PlayerPose
        let cue: ReplayAthleteInteractionCue?
    }

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        if let scenario = FootballReferenceScenarios.all.first {
            // A fresh cache prunes previous weak-root entries after each test
            // has released its strong root/skin locals. Not a renderer drain.
            let empty = Entity(), marks = Entity()
            marks.name = "marks-root"; empty.addChild(marks)
            update(empty, scenario, time: 0, view: .firstPerson, detail: .balanced)
            while let child = empty.children.first { child.removeFromParent() }
        }
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplayArmCutTimeline.resetCountersForTesting()
        ReplaySkinnedAthleteCutWeight.resetSampleCountForTesting()
        ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
        super.tearDown()
    }

    func testNativeRootBankBindsFullTrackAndRecordsColdPreparation158() async throws {
        let context = try await prepare()
        ReplayArmCutTimeline.resetCountersForTesting()
        ReplaySkinnedAthleteCutWeight.resetSampleCountForTesting()
        let start = DispatchTime.now().uptimeNanoseconds
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let coldNeighbourCalls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
        defer { while let child = root.children.first { child.removeFromParent() } }
        let bank = PitchSceneFactory.armCutTimelinesForTesting(in: root)
        let impactID = PlayerRagdollCue.authoredDemo(for: context.scenario)?.playerID
        let expected = Set(context.scenario.players.filter { !$0.isGoalkeeper && $0.id != impactID }.map(\.id))
        XCTAssertEqual(Set(bank.keys), expected)
        XCTAssertNotNil(bank["arg-10"], "A contact actor is not excluded for its entire track")
        XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root).isEmpty)
        let evaluations = bank.values.reduce(0) { $0 + $1.metricsForTesting.evaluatedRawSampleCount }
        XCTAssertEqual(ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting, evaluations)
        let originalTables = bank.mapValues(\.knotsForTesting)
        let track = try XCTUnwrap(context.scenario.player(id: "arg-10"))
        let timeline = try XCTUnwrap(bank[track.id])
        let time = 1.825, locomotion = track.locomotion(at: time)
        XCTAssertLessThan(time, context.scenario.duration)
        let admission = try XCTUnwrap(timeline.admission(at: time, locomotion: locomotion))
        XCTAssertNotNil(admission.matchingWeight(sourceCommit: ReplaySkinnedAthleteCutPhase.sourceCommit,
            track: track, at: time, locomotion: locomotion))

        // Same ID, changed actual telemetry; neither the root bank nor typed
        // admission may be identified by player ID alone.
        let first = try XCTUnwrap(track.keyframes.first)
        let changed = PlayerTrack(id: track.id, displayName: track.displayName, role: track.role,
            shirtNumber: track.shirtNumber, team: track.team, isGoalkeeper: false,
            keyframes: track.keyframes.map { .init(time: $0.time, position: first.position,
                                                  facingDegrees: first.facingDegrees) })
        XCTAssertNotEqual(track, changed)
        XCTAssertNil(admission.matchingWeight(sourceCommit: ReplaySkinnedAthleteCutPhase.sourceCommit,
            track: changed, at: time, locomotion: locomotion))
        let alternate = replacingPlayers(context.scenario, with: [changed])
        let changedRoot = PitchSceneFactory.makeMatchRoot(for: alternate, nativeRecording: context.recording)
        defer { while let child = changedRoot.children.first { child.removeFromParent() } }
        let changedBank = PitchSceneFactory.armCutTimelinesForTesting(in: changedRoot)
        XCTAssertEqual(Set(changedBank.keys), [track.id])
        let changedTimeline = try XCTUnwrap(changedBank[track.id])
        let changedAdmission = try XCTUnwrap(changedTimeline.admission(at: time, locomotion: changed.locomotion(at: time)))
        XCTAssertNil(changedAdmission.matchingWeight(sourceCommit: ReplaySkinnedAthleteCutPhase.sourceCommit,
            track: track, at: time, locomotion: changed.locomotion(at: time)))
        XCTAssertNotEqual(changedTimeline.knotsForTesting, timeline.knotsForTesting)
        XCTAssertEqual(PitchSceneFactory.armCutTimelinesForTesting(in: root).mapValues(\.knotsForTesting), originalTables)
        try attach(["scenario": context.scenario.id, "rootConstructionNanoseconds": elapsed,
            "armTimelineBuildNanoseconds": PitchSceneFactory.armCutBuildNanosecondsForTesting(in: root),
            "timelineCount": bank.count, "knotCount": bank.values.reduce(0) { $0 + $1.metricsForTesting.knotCount },
            "rawSampleCount": bank.values.reduce(0) { $0 + $1.metricsForTesting.rawSampleCount },
            "evaluatedRawSampleCount": evaluations,
            "coldNeighbourLocomotionRequests": coldNeighbourCalls,
            "skippedMidpointCount": bank.values.reduce(0) { $0 + $1.metricsForTesting.skippedMidpointCount },
            "storedWeightBytes": bank.values.reduce(0) { $0 + $1.metricsForTesting.storageBytes },
            "scope": "One full actual rebound root after asset/native prewarm; nested arm build is included in root time. Float payload only, not retained track/Array/Dictionary or GPU bytes. No timing threshold. Changed-track isolation uses a separate stationary telemetry fixture with the same ID, not a new native bake."],
            name: "arm-cut-root-cache-158")
    }

    func testFactoryGraphicsAndPOVReuseTablesWithExactRewindAndNoExtraSampling158() async throws {
        let context = try await prepare()
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        defer { while let child = root.children.first { child.removeFromParent() } }
        let original = PitchSceneFactory.armCutTimelinesForTesting(in: root).mapValues(\.knotsForTesting)
        let buildTime = PitchSceneFactory.armCutBuildNanosecondsForTesting(in: root)
        let coldCalls = ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting
        var rows: [[String: Any]] = []
        var seenNear = false, seenLow = false
        for detail in ReplayPlayerDetail.allCases {
            for view in [ReplayViewMode.tacticalTable, .firstPerson] {
                let time = 1.825
                XCTAssertLessThan(time, context.scenario.duration)
                update(root, context.scenario, time: time, view: view, detail: detail)
                let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
                XCTAssertFalse(skins.isEmpty)
                seenNear = seenNear || skins.values.contains { $0.detail == .near }
                seenLow = seenLow || skins.values.contains { $0.detail == .lowDetail }
                if view == .firstPerson {
                    XCTAssertNil(skins[context.scenario.defaultPerspectiveID])
                    XCTAssertLessThanOrEqual(skins.values.filter { $0.detail == .near }.count, 2)
                }
                for skin in skins.values { skin.disablesArmCutSmoothingForTesting = true }
                ReplaySkinnedAthleteCutWeight.resetSampleCountForTesting()
                ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
                update(root, context.scenario, time: time, view: view, detail: detail)
                let oldCalls = ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
                let oldClips = ReplaySkinnedAthleteMotion.clipSampleCountsForTesting
                let old = try snapshot(root)
                for skin in skins.values { skin.disablesArmCutSmoothingForTesting = false }
                ReplaySkinnedAthleteCutWeight.resetSampleCountForTesting()
                ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
                update(root, context.scenario, time: time, view: view, detail: detail)
                XCTAssertEqual(ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount, oldCalls)
                XCTAssertEqual(ReplaySkinnedAthleteMotion.clipSampleCountsForTesting, oldClips)
                let candidate = try snapshot(root)
                XCTAssertEqual(candidate.graph, old.graph)
                XCTAssertEqual(candidate.actors, old.actors)
                XCTAssertEqual(candidate.ball, old.ball)
                for (id, skin) in skins {
                    XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root)[id] === skin)
                    for name in ["leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "leftToe", "rightToe"] {
                        let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
                        XCTAssertEqual(candidate.joints[id]![index].rotation.vector, old.joints[id]![index].rotation.vector)
                    }
                }
                update(root, context.scenario, time: 2.1, view: view, detail: detail)
                update(root, context.scenario, time: time, view: view, detail: detail)
                XCTAssertEqual(try snapshot(root), candidate)
                XCTAssertEqual(PitchSceneFactory.armCutTimelinesForTesting(in: root).mapValues(\.knotsForTesting), original)
                XCTAssertEqual(PitchSceneFactory.armCutBuildNanosecondsForTesting(in: root), buildTime)
                XCTAssertEqual(ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting, coldCalls)
                rows.append(["detail": detail.rawValue, "view": view.rawValue, "skins": skins.count,
                    "near": skins.values.filter { $0.detail == .near }.count,
                    "low": skins.values.filter { $0.detail == .lowDetail }.count,
                    "neighbourLocomotionRequestsPerUpdate": oldCalls])
            }
        }
        XCTAssertTrue(seenNear); XCTAssertTrue(seenLow)
        XCTAssertGreaterThan(ReplayArmCutTimeline.warmAdmissionCountForTesting, 0)
        try attach(["rows": rows, "scope": "Same root across Balanced/Full Squad and table/POV. Untimed exact graph, actor/ball trajectories, leg rotations and rewind checks. Candidate adds zero cold policy calls and zero old-cut neighbour locomotion requests."],
                   name: "arm-cut-factory-reuse-158")
    }

    func testNearLowProviderABCostAndWarmSourceSampling158() async throws {
        let context = try await prepare()
        let track = try XCTUnwrap(context.scenario.player(id: "arg-10"))
        let cues = try interactionCues(context, track: track)
        let first = try XCTUnwrap(context.recording.samples.first), last = try XCTUnwrap(context.recording.samples.last)
        let timeline = try XCTUnwrap(ReplayArmCutTimeline(track: track, interactions: cues,
            duration: last.time - first.time, startTime: first.time))
        let inputs = (0..<40).map { index -> Input in
            let time = 1.6 + Double(index) / 60
            let cue = cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
            return .init(time: time, locomotion: track.locomotion(at: time),
                         presentation: track.presentationPose(at: time), cue: cue)
        }
        XCTAssertTrue(inputs.allSatisfy { $0.time >= first.time && $0.time <= last.time })
        XCTAssertTrue(inputs.contains {
            (timeline.admission(at: $0.time, locomotion: $0.locomotion)?.envelopeWeight ?? 0) > 0
        }, "Benchmark must include positive prepared admission, not just nil/zero lookups")
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            defer { skin.root.removeFromParent() }
            func apply(_ input: Input, candidate: Bool) -> Bool {
                skin.update(at: input.time, track: track, locomotion: input.locomotion, lookTarget: nil,
                    ballAction: nil, interaction: input.cue, presentationPose: input.presentation,
                    allowsTrackLocomotionSampling: true,
                    armCutAdmission: candidate ? timeline.admission(at: input.time, locomotion: input.locomotion) : nil)
            }
            var maximumSuppression: Float = 0
            for input in inputs {
                XCTAssertTrue(apply(input, candidate: true))
                maximumSuppression = max(maximumSuppression, skin.armCutSuppressionForTesting)
            }
            XCTAssertGreaterThan(maximumSuppression, 0, "A/B must exercise an actual arm-weight change")
            var times = [[UInt64](), [UInt64]()]
            var calls = [0, 0], clips = [0, 0], valid = true, admissions = 0
            let coldBefore = ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting
            for batch in 0..<12 {
                for variant in batch.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                    ReplaySkinnedAthleteCutWeight.resetSampleCountForTesting()
                    ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
                    let warmBefore = ReplayArmCutTimeline.warmAdmissionCountForTesting
                    let start = DispatchTime.now().uptimeNanoseconds
                    for input in inputs { valid = apply(input, candidate: variant == 1) && valid }
                    times[variant].append(DispatchTime.now().uptimeNanoseconds - start)
                    calls[variant] += ReplaySkinnedAthleteCutWeight.neighbourLocomotionSampleCount
                    clips[variant] += ReplaySkinnedAthleteMotion.clipSampleCountsForTesting.total
                    admissions += ReplayArmCutTimeline.warmAdmissionCountForTesting - warmBefore
                }
            }
            XCTAssertTrue(valid)
            XCTAssertEqual(calls[0], calls[1]); XCTAssertEqual(clips[0], clips[1])
            XCTAssertEqual(admissions, 12 * inputs.count)
            XCTAssertEqual(ReplayArmCutTimeline.coldPolicyEvaluationCountForTesting, coldBefore)
            for variant in 0...1 {
                let sorted = times[variant].sorted()
                rows.append(["detail": detail == .near ? "near" : "low", "candidate": variant == 1,
                    "batches": sorted.count, "updatesPerBatch": inputs.count,
                    "medianBatchNanoseconds": sorted[sorted.count / 2],
                    "maximumBatchNanoseconds": sorted.last!, "batchNanoseconds": times[variant],
                    "maximumUntimedWarmupSuppression": maximumSuppression,
                    "neighbourLocomotionRequests": calls[variant], "sourceClipSamples": clips[variant]])
            }
        }
        try attach(["player": track.id, "rows": rows,
            "scope": "Unpaced CPU Provider.update only, one live skin per detail, precomputed authoritative inputs, alternating 12 paired 40-update batches. Candidate includes typed admission construction and full-track binding; old path supplies nil. No assertion, pose oracle, renderer, or source-input sampling inside timing. Cold preparation excluded. No FPS or timing acceptance threshold."],
            name: "arm-cut-provider-cost-158")
    }

    private func prepare() async throws -> Context {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try ReplayArmLOD147Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm(); try ReplayStrategyBallProvider.prewarm()
        let context = try await ReplayArmLOD147Probe.context()
        try ReplayAthleteFactory.prewarm(for: context.scenario.players, lods: [.near, .far])
        return context
    }
    private func update(_ root: Entity, _ scenario: ReplayScenario, time: Double,
                        view: ReplayViewMode, detail: ReplayPlayerDetail) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil, playerDetail: detail)
    }
    private func snapshot(_ root: Entity) throws -> State {
        var paths: [String] = [], pending: [(Entity, String)] = [(root, root.name)]
        while let (entity, path) = pending.popLast() {
            paths.append(path)
            for (index, child) in entity.children.enumerated() { pending.append((child, "\(path)/\(index):\(child.name)")) }
        }
        let players = try XCTUnwrap(root.findEntity(named: "players-root"))
        let ball = try XCTUnwrap(root.findEntity(named: "ball"))
        return .init(graph: paths.sorted(), actors: Dictionary(uniqueKeysWithValues: players.children.map { ($0.name, $0.transform) }),
                     ball: ball.transform, joints: PitchSceneFactory.skinnedAthletesForTesting(in: root).mapValues { $0.model.jointTransforms })
    }
    private func interactionCues(_ context: Context, track: PlayerTrack) throws -> [ReplayAthleteInteractionCue] {
        try context.recording.touches.filter { $0.playerID == track.id }.map {
            .init(playerID: track.id, kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
    }
    private func replacingPlayers(_ s: ReplayScenario, with players: [PlayerTrack]) -> ReplayScenario {
        .init(id: s.id, kind: s.kind, title: s.title, strapline: s.strapline, matchContext: s.matchContext,
              objective: s.objective, coachPrompt: s.coachPrompt, proofPoint: s.proofPoint, duration: s.duration,
              defaultViewMode: s.defaultViewMode, defaultPerspectiveID: s.defaultPerspectiveID,
              featuredPerspectiveIDs: s.featuredPerspectiveIDs, players: players, ball: s.ball,
              moments: s.moments, coachMarks: s.coachMarks, formationTargets: s.formationTargets)
    }
    private func attach(_ object: [String: Any], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
