import Dispatch
import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Explicit production player-detail choices. Timings cover Factory.update without a
/// renderer; hierarchy/material slots are not visible draws or headset FPS.
@MainActor
final class ReplaySquadSkinCost147Tests: XCTestCase {
    private struct NodeState: Equatable {
        let transform: Transform
        let joints: [Transform]
    }
    private struct Trajectory: Equatable {
        let presentation: Transform
        let players: [Transform]
        let ball: Transform
    }
    private struct State: Equatable {
        let trajectory: Trajectory
        let visible: [String: NodeState]
    }
    private struct Result {
        let report: [String: Any]
        let trajectories: [Double: Trajectory]
    }
    private final class WeakSkin {
        weak var value: ReplaySkinnedAthleteInstance?
        init(_ value: ReplaySkinnedAthleteInstance) { self.value = value }
    }
    private final class Resources {
        // Strong refs prevent recycled native addresses from masquerading as
        // sharing. This bank is local to one untimed case, not a runtime cache.
        var meshes: [ObjectIdentifier: MeshResource] = [:]
        var meshSizes: [ObjectIdentifier: (vertices: Int, triangles: Int)] = [:]
        var skinMeshes: [ReplaySkinnedAthleteProvider.Detail: Set<ObjectIdentifier>] = [:]
        // Material getters may return fresh Swift wrappers (visionOS 26.5).
        // Count public resource equality, not wrappers or private GPU storage.
        var skinTextures: [TextureResource] = []
    }

    override func setUp() {
        super.setUp()
        reset()
    }

    override func tearDown() {
        reset()
        super.tearDown()
    }

    private func reset() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
    }

    func testActualFiveDemoFullSquadSkinExperimentCPUAndResources147() async throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Default admitted assets only")
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        var reports: [[String: Any]] = []
        for scenario in FootballReferenceScenarios.all {
            let playersBefore = scenario.players, ballBefore = scenario.ball
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            XCTAssertEqual(recording.touches.count, plan.count)
            XCTAssertEqual(recording.missedTouchCount, 0)
            let positionsBefore = recording.samples.map(\.position)
            let velocitiesBefore = recording.samples.map(\.velocity)
            let orientationsBefore = recording.samples.map { $0.orientation.vector }
            try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
            let regular = (0...8).map { scenario.duration * Double($0) / 8 }
            let contacts = recording.touches.flatMap { [$0.time - 1.0 / 30, $0.time, $0.time + 1.0 / 30] }
            let forward = Array(Set((regular + contacts).map { min(max($0, 0), scenario.duration) })).sorted()
            let paused = recording.touches.last?.time ?? scenario.duration * 0.5
            XCTAssertLessThanOrEqual(forward.count * 2 + 6, 60)
            for view in [ReplayViewMode.tacticalTable, .firstPerson] {
                let baseline = try measure(scenario, recording: recording, view: view,
                    playerDetail: .balanced, forward: forward, paused: paused)
                let candidate = try measure(scenario, recording: recording, view: view,
                    playerDetail: .fullSquad, forward: forward, paused: paused)
                XCTAssertEqual(candidate.trajectories, baseline.trajectories,
                    "Admission cannot alter the ball, player anchors or view transform")
                reports.append(baseline.report); reports.append(candidate.report)
            }
            XCTAssertEqual(scenario.players, playersBefore)
            XCTAssertEqual(scenario.ball, ballBefore)
            XCTAssertEqual(recording.samples.map(\.position), positionsBefore)
            XCTAssertEqual(recording.samples.map(\.velocity), velocitiesBefore)
            XCTAssertEqual(recording.samples.map { $0.orientation.vector }, orientationsBefore)
        }
        XCTAssertEqual(reports.count, 20)
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let report: [String: Any] = [
            "cases": reports, "caseCount": reports.count,
            "scope": "Explicit production Balanced and Full squad selections; compiler optimization is specified externally in the test build, not inferred here.",
            "selectionSource": "ReplayPlayerDetail argument; fullSquadFlag is a comparison alias for playerDetail == fullSquad, not the disabled DEBUG override",
            "debugOverrideEnabled": PitchSceneFactory.fullSquadSkinsForTesting,
            "timed": "PitchSceneFactory.update only, including its existing DEBUG counters and normal membership changes; initial population and paused quality switches are separate from the warmed phase timings",
            "excluded": "Native physics bake, asset prewarm, graph construction, warmup, one full-membership normalization update before policy switches, assertions, readbacks, census, renderer/GPU/compositor, UI/input and headset work",
            "resourceScope": "Retained and enabled hierarchy, not frustum visibility, GPU draws or resident GPU bytes. Strong mesh/texture references held during each untimed census.",
            "determinismScope": "Exact ball/player/view transforms, repeated poses and reverse common visible variants; LOD membership itself has intentional hysteresis.",
            "productionSkinCap": ReplaySkinnedAthleteProvider.maximumConcurrentInstances,
            "productionFullSquadSkinCap": ReplayPlayerDetail.fullSquad.maximumSkinnedPlayers,
            "productionPOVNearCap": PitchSceneFactory.firstPersonDetailedRigLimit,
            "notFPS": true, "notColdStart": true, "notPacedPlayback": true,
            "defaultBalancedBudgetUnchanged": true
        ]
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-SquadSkins148-FactoryCPUAndResources.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }

    private func measure(_ scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                         view: ReplayViewMode, playerDetail: ReplayPlayerDetail,
                         forward: [Double], paused: Double) throws -> Result {
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let fullSquad = playerDetail == .fullSquad
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        let phases: [(String, [Double])] = [("forward", forward), ("reverse", Array(forward.reversed())),
                                          ("paused", Array(repeating: paused, count: 6))]
        XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root).isEmpty)
        let initialPopulation = timedPopulationUpdate(root, scenario, view,
            time: try XCTUnwrap(forward.first), playerDetail: playerDetail,
            label: "first-update-after-graph-construction")
        _ = try snapshot(root, scenario: scenario, recording: recording, view: view,
                         time: try XCTUnwrap(forward.first))
        for _ in 0..<3 {
            update(root, scenario, view, time: try XCTUnwrap(forward.first), playerDetail: playerDetail)
        }
        let loadsBefore = loadCounts()
        let indexBefore = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        let bindingsBefore = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        let clonesBefore = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
        var timing: [[String: Any]] = []
        for (phase, times) in phases {
            var durations: [UInt64] = []
            durations.reserveCapacity(times.count)
            for time in times {
                let start = DispatchTime.now().uptimeNanoseconds
                update(root, scenario, view, time: time, playerDetail: playerDetail)
                durations.append(DispatchTime.now().uptimeNanoseconds &- start)
            }
            let sorted = durations.sorted(), middle = durations.count / 2
            let median = durations.count.isMultiple(of: 2)
                ? (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2 : Double(sorted[middle])
            timing.append(["phase": phase, "updates": times.count, "timesSeconds": times,
                "rawNanoseconds": durations, "medianNanoseconds": median,
                "p95Nanoseconds": sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)],
                "maximumNanoseconds": try XCTUnwrap(sorted.last)])
        }
        let clonesAfter = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
        let indexAfter = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        let bindingsAfter = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        let work = PitchSceneFactory.annotationSceneWork
        let visibilityVisits = PitchSceneFactory.proceduralVisibilityNodeVisits
        let visibilityWrites = PitchSceneFactory.proceduralVisibilityModelWrites
        let timedUpdates = phases.reduce(0) { $0 + $1.1.count }
        XCTAssertEqual(loadCounts(), loadsBefore)
        XCTAssertEqual(indexAfter.entityIndexBuilds, indexBefore.entityIndexBuilds)
        XCTAssertEqual(indexAfter.poseRefreshes - indexBefore.poseRefreshes, timedUpdates)
        XCTAssertEqual(ReplayAthleteMotion.ballActionSampleCount, 0)
        XCTAssertEqual(work.markTreeBuilds, 0)

        // Readback and resource walks are a distinct, untimed pass.
        let resources = Resources()
        var reference: [Double: State] = [:], trajectories: [Double: Trajectory] = [:]
        var counts: [[String: Int]] = [], admissions: [[String: Any]] = []
        var commonReverseNodes = 0, nearCreations = 0, lowCreations = 0
        var previousSkins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        for (phase, times) in phases {
            for time in times {
                update(root, scenario, view, time: time, playerDetail: playerDetail)
                let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
                for (id, skin) in skins where previousSkins[id] !== skin {
                    if skin.detail == .near { nearCreations += 1 } else { lowCreations += 1 }
                }
                previousSkins = skins
                let state = try snapshot(root, scenario: scenario, recording: recording, view: view, time: time)
                if let prior = reference[time] {
                    XCTAssertEqual(state.trajectory, prior.trajectory)
                    for (path, node) in state.visible {
                        if let expected = prior.visible[path] {
                            XCTAssertEqual(node, expected, "Same visible variant on reverse: \(scenario.id)/\(time)/\(path)")
                            if phase == "reverse" { commonReverseNodes += 1 }
                        }
                    }
                } else { reference[time] = state }
                trajectories[time] = state.trajectory
                let count = census(root, resources: resources)
                counts.append(count)
                let isPOV = view == .firstPerson
                let expectedSkins = fullSquad ? scenario.players.count - (isPOV ? 1 : 0)
                    : (isPOV ? 2 : 4)
                XCTAssertEqual(skins.count, expectedSkins)
                XCTAssertEqual(count["enabledSkinRoots"], expectedSkins)
                XCTAssertEqual(count["retainedFarRigs"], scenario.players.count)
                XCTAssertEqual(count["enabledFarRigs"], scenario.players.count - expectedSkins - (isPOV ? 1 : 0))
                XCTAssertEqual(count["enabledNearSkins"], isPOV ? 2 : 1)
                XCTAssertEqual(count["enabledLowSkins"], expectedSkins - (isPOV ? 2 : 1))
                admissions.append(["phase": phase, "time": time,
                    "near": skins.filter { $0.value.detail == .near }.keys.sorted(),
                    "low": skins.filter { $0.value.detail == .lowDetail }.keys.sorted(),
                    "selfHidden": isPOV, "counts": count])
            }
        }
        previousSkins.removeAll()
        XCTAssertGreaterThan(commonReverseNodes, 0)
        XCTAssertEqual(resources.skinMeshes[.near]?.count, 1)
        XCTAssertEqual(resources.skinMeshes[.lowDetail]?.count ?? 0, fullSquad || view != .firstPerson ? 1 : 0)
        XCTAssertEqual(loadCounts(), loadsBefore)

        // Same-time warm-cache probe, separate from timed forward/reverse work.
        do {
            update(root, scenario, view, time: paused, playerDetail: playerDetail)
            let warmSkins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            let warmCount = census(root, resources: resources)
            let warmState = try snapshot(root, scenario: scenario, recording: recording, view: view, time: paused)
            let warmClones = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
            let warmBindings = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
            for _ in 0..<20 { update(root, scenario, view, time: paused, playerDetail: playerDetail) }
            let afterWarm = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            XCTAssertEqual(Set(afterWarm.keys), Set(warmSkins.keys))
            for (id, skin) in warmSkins { XCTAssertTrue(afterWarm[id] === skin) }
            XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, warmClones)
            XCTAssertEqual(PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root), warmBindings)
            XCTAssertEqual(census(root, resources: resources), warmCount)
            XCTAssertEqual(try snapshot(root, scenario: scenario, recording: recording, view: view, time: paused), warmState)
            XCTAssertEqual(loadCounts(), loadsBefore)
        }
        var ranges: [String: [Int]] = [:]
        for key in try XCTUnwrap(counts.first).keys {
            let values = counts.compactMap { $0[key] }
            ranges[key] = [try XCTUnwrap(values.min()), try XCTUnwrap(values.max())]
        }
        // Normalize both case variants to the same full membership/history.
        // Otherwise a sticky small set from playback can legitimately differ
        // from the closest small set retained after full-capacity admission.
        update(root, scenario, view, time: paused, playerDetail: .fullSquad)
        let normalization: [String: Any]
        do {
            let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            normalization = ["time": paused, "fullSquadFlag": true,
                "playerDetail": ReplayPlayerDetail.fullSquad.rawValue, "untimedUpdates": 1,
                "nearIDs": skins.filter { $0.value.detail == .near }.keys.sorted(),
                "lowIDs": skins.filter { $0.value.detail == .lowDetail }.keys.sorted()]
            XCTAssertEqual(skins.count, scenario.players.count - (view == .firstPerson ? 1 : 0))
        }
        // Real, retained scene at a fixed paused time. This measures switch
        // work only, excluding normalization, graph construction and readbacks.
        var qualitySwitches: [[String: Any]] = [], switchStates: [ReplayPlayerDetail: State] = [:]
        var switchTrajectory: Trajectory?
        for (index, selection) in [ReplayPlayerDetail.balanced, .fullSquad, .balanced, .fullSquad].enumerated() {
            var switchReceipt = timedPopulationUpdate(root, scenario, view, time: paused,
                playerDetail: selection,
                label: index == 0 ? "establish-false" : "switch-\(index)")
            let state = try snapshot(root, scenario: scenario, recording: recording, view: view, time: paused)
            let context = "\(scenario.id)/\(view.rawValue)/case=\(playerDetail.rawValue)/selection=\(selection.rawValue)/index=\(index)"
            let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            switchReceipt["index"] = index
            switchReceipt["nearIDs"] = skins.filter { $0.value.detail == .near }.keys.sorted()
            switchReceipt["lowIDs"] = skins.filter { $0.value.detail == .lowDetail }.keys.sorted()
            if let prior = switchStates[selection] {
                let currentKeys = Set(state.visible.keys), priorKeys = Set(prior.visible.keys)
                let added = currentKeys.subtracting(priorKeys).sorted()
                let removed = priorKeys.subtracting(currentKeys).sorted()
                let changed = currentKeys.intersection(priorKeys).filter {
                    state.visible[$0] != prior.visible[$0]
                }.sorted()
                XCTAssertTrue(state.trajectory == prior.trajectory, "\(context): repeated-policy trajectory changed")
                XCTAssertTrue(currentKeys == priorKeys,
                    "\(context): visible keys differ; added \(pathSummary(added)); removed \(pathSummary(removed))")
                XCTAssertTrue(changed.isEmpty,
                    "\(context): common visible poses changed: \(pathSummary(changed))")
                switchReceipt["repeatedPolicyTrajectoryExact"] = state.trajectory == prior.trajectory
                switchReceipt["addedVisiblePaths"] = added
                switchReceipt["removedVisiblePaths"] = removed
                switchReceipt["changedCommonVisiblePaths"] = changed
            }
            switchStates[selection] = state
            if let prior = switchTrajectory {
                XCTAssertTrue(state.trajectory == prior, "\(context): cross-policy trajectory changed")
            }
            switchTrajectory = state.trajectory
            let expectedSkins = selection == .fullSquad ? scenario.players.count - (view == .firstPerson ? 1 : 0)
                : (view == .firstPerson ? 2 : 4)
            XCTAssertEqual(skins.count, expectedSkins, context)
            qualitySwitches.append(switchReceipt)
        }
        XCTAssertEqual(loadCounts(), loadsBefore)
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        return Result(report: [
            "scenario": scenario.id, "view": view.rawValue, "fullSquadFlag": fullSquad,
            "playerDetail": playerDetail.rawValue, "debugOverrideEnabled": false,
            "perspective": scenario.defaultPerspectiveID, "timing": timing, "timedUpdates": timedUpdates,
            "untimedVerificationUpdates": timedUpdates + 21, "initialWarmupUpdates": 3,
            "initialPopulation": initialPopulation, "pausedQualitySwitches": qualitySwitches,
            "qualitySwitchNormalization": normalization,
            "qualitySwitchNormalizationUntimedUpdates": 1,
            "additionalPopulationAndSwitchTimedUpdates": 5,
            "nativeSamples": recording.samples.count, "nativeTouches": recording.touches.count,
            "missedTouches": recording.missedTouchCount, "resourceMinMax": ranges, "admissionFrames": admissions,
            "distinctNearSkinMeshes": resources.skinMeshes[.near]?.count ?? 0,
            "distinctLowSkinMeshes": resources.skinMeshes[.lowDetail]?.count ?? 0,
            "distinctSkinBaseAndNormalTextures": resources.skinTextures.count,
            "lowCloneAttemptsDuringTiming": clonesAfter - clonesBefore,
            "nearReplacementsObservedUntimed": nearCreations, "lowReplacementsObservedUntimed": lowCreations,
            "warmSameTimeUpdates": 20, "warmNewLowClones": 0, "warmSkinIdentitiesExact": true,
            "warmResourceCountsExact": true, "loadsBefore": loadsBefore, "loadsAfter": loadCounts(),
            "reverseCommonVisibleNodeComparisons": commonReverseNodes,
            "playerIndexBuildsDuringTiming": indexAfter.entityIndexBuilds - indexBefore.entityIndexBuilds,
            "bindingResolutionsDuringTiming": bindingsAfter.hierarchyResolutions - bindingsBefore.hierarchyResolutions,
            "bindingInvalidationsDuringTiming": bindingsAfter.invalidations - bindingsBefore.invalidations,
            "annotationSyncsDuringTiming": work.syncCalls, "annotationTreeBuildsDuringTiming": work.markTreeBuilds,
            "visibilityNodeVisitsDuringTiming": visibilityVisits, "visibilityModelWritesDuringTiming": visibilityWrites
        ], trajectories: trajectories)
    }

    private func pathSummary(_ paths: [String]) -> String {
        "\(paths.count) paths \(Array(paths.prefix(12)))\(paths.count > 12 ? " (full list in receipt)" : "")"
    }

    private func timedPopulationUpdate(_ root: Entity, _ scenario: ReplayScenario, _ view: ReplayViewMode,
                                       time: Double, playerDetail: ReplayPlayerDetail, label: String) -> [String: Any] {
        // Weak refs include destruction cost without mistaking a recycled
        // allocation address for an unchanged skin instance.
        let before = PitchSceneFactory.skinnedAthletesForTesting(in: root).mapValues(WeakSkin.init)
        let clones = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
        let loads = loadCounts()
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        let start = DispatchTime.now().uptimeNanoseconds
        update(root, scenario, view, time: time, playerDetail: playerDetail)
        let duration = DispatchTime.now().uptimeNanoseconds &- start
        let after = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        let newSkins = after.filter { before[$0.key]?.value !== $0.value }
        XCTAssertEqual(loadCounts(), loads)
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        return ["label": label, "time": time, "fullSquadFlag": playerDetail == .fullSquad,
            "playerDetail": playerDetail.rawValue, "debugOverrideEnabled": PitchSceneFactory.fullSquadSkinsForTesting,
            "nanoseconds": duration, "skinCountBefore": before.count, "skinCountAfter": after.count,
            "nearAfter": after.values.filter { $0.detail == .near }.count,
            "lowAfter": after.values.filter { $0.detail == .lowDetail }.count,
            "newNearSkinInstances": newSkins.values.filter { $0.detail == .near }.count,
            "newLowSkinInstances": newSkins.values.filter { $0.detail == .lowDetail }.count,
            "lowCloneAttemptDelta": ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount - clones,
            "loadCountersBefore": loads, "loadCountersAfter": loadCounts(),
            "nativeAssetsStillPrewarmed": true,
            "loadCounterScope": "Existing far palette, texture, face and kit counters; native assets have readiness checks, not an I/O counter"]
    }

    private func snapshot(_ root: Entity, scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                          view: ReplayViewMode, time: Double) throws -> State {
        let players = try XCTUnwrap(root.findEntity(named: "players-root"))
        let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        let variants = Dictionary(uniqueKeysWithValues: skins.values.map {
            (ObjectIdentifier($0.root), $0.detail == .near ? "#near" : "#low")
        })
        var anchors: [Transform] = [], visible: [String: NodeState] = [:]
        @discardableResult
        func visit(_ entity: Entity, path: String) -> Bool {
            guard entity.isEnabled else { return false }
            let path = path + (variants[ObjectIdentifier(entity)] ?? "")
            var containsModel = entity.components[ModelComponent.self] != nil
            var ordinals: [String: Int] = [:]
            for child in entity.children {
                let ordinal = ordinals[child.name, default: 0]
                ordinals[child.name] = ordinal + 1
                containsModel = visit(child, path: path + "/\(child.name)[\(ordinal)]") || containsModel
            }
            if containsModel {
                visible[path] = .init(transform: entity.transform, joints: (entity as? ModelEntity)?.jointTransforms ?? [])
            }
            return containsModel
        }
        for player in scenario.players {
            let entity = try XCTUnwrap(players.children.first { $0.name == "player-\(player.id)" })
            let pose = player.presentationPose(at: time)
            XCTAssertEqual(entity.position, [pose.position.x, 0, pose.position.z])
            anchors.append(entity.transform)
            if view == .firstPerson, player.id == scenario.defaultPerspectiveID {
                XCTAssertNil(skins[player.id])
                XCTAssertFalse(try XCTUnwrap(entity.children.first { $0.name == "table-marker" }).isEnabled)
                XCTAssertFalse(entity.children.first { $0.name == "full-rig" }?.isEnabled ?? false)
                XCTAssertFalse(try XCTUnwrap(entity.children.first { $0.name == "interaction-target" }).isEnabled)
            }
            visit(entity, path: player.id)
        }
        let ball = try XCTUnwrap(root.findEntity(named: "ball")), expected = recording.pose(at: time)
        XCTAssertEqual(ball.position, [expected.position.x, max(expected.height, 0.11), expected.position.z])
        return .init(trajectory: .init(presentation: root.transform, players: anchors, ball: ball.transform), visible: visible)
    }

    private func census(_ root: Entity, resources: Resources) -> [String: Int] {
        let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        let details = Dictionary(uniqueKeysWithValues: skins.values.map { (ObjectIdentifier($0.root), $0.detail) })
        var count = ["residentEntities": 0, "retainedModels": 0, "enabledModels": 0,
            "retainedMaterialSlots": 0, "enabledMaterialSlots": 0, "retainedSkinRoots": 0,
            "enabledSkinRoots": 0, "enabledNearSkins": 0, "enabledLowSkins": 0,
            "retainedNearRigs": 0, "retainedFarRigs": 0, "enabledFarRigs": 0,
            "enabledJointModels": 0, "enabledJointTransforms": 0,
            "enabledVerticesPerInstance": 0, "enabledTrianglesPerInstance": 0]
        var currentMeshes = Set<ObjectIdentifier>()
        func visit(_ entity: Entity, ancestorsEnabled: Bool, detail inherited: ReplaySkinnedAthleteProvider.Detail?) {
            count["residentEntities", default: 0] += 1
            let enabled = ancestorsEnabled && entity.isEnabled
            let ownDetail = details[ObjectIdentifier(entity)], detail = ownDetail ?? inherited
            if ownDetail != nil {
                count["retainedSkinRoots", default: 0] += 1
                if enabled {
                    count["enabledSkinRoots", default: 0] += 1
                    count[ownDetail == .near ? "enabledNearSkins" : "enabledLowSkins", default: 0] += 1
                }
            }
            if entity.name == "full-rig" { count["retainedNearRigs", default: 0] += 1 }
            if entity.name == "table-marker" {
                count["retainedFarRigs", default: 0] += 1
                if enabled { count["enabledFarRigs", default: 0] += 1 }
            }
            if let component = entity.components[ModelComponent.self] {
                let mesh = component.mesh, id = ObjectIdentifier(mesh)
                resources.meshes[id] = mesh; currentMeshes.insert(id)
                if resources.meshSizes[id] == nil {
                    let parts = mesh.contents.models.flatMap { Array($0.parts) }
                    resources.meshSizes[id] = (parts.reduce(0) { $0 + $1.positions.count },
                        parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 })
                }
                count["retainedModels", default: 0] += 1
                count["retainedMaterialSlots", default: 0] += component.materials.count
                if enabled {
                    count["enabledModels", default: 0] += 1
                    count["enabledMaterialSlots", default: 0] += component.materials.count
                    count["enabledVerticesPerInstance", default: 0] += resources.meshSizes[id]?.vertices ?? 0
                    count["enabledTrianglesPerInstance", default: 0] += resources.meshSizes[id]?.triangles ?? 0
                }
                if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
                    if enabled {
                        count["enabledJointModels", default: 0] += 1
                        count["enabledJointTransforms", default: 0] += model.jointTransforms.count
                    }
                    if let detail {
                        resources.skinMeshes[detail, default: []].insert(id)
                        for material in component.materials {
                            guard let physical = material as? PhysicallyBasedMaterial else { continue }
                            for texture in [physical.baseColor.texture?.resource, physical.normal.texture?.resource].compactMap({ $0 }) {
                                if !resources.skinTextures.contains(texture) {
                                    resources.skinTextures.append(texture)
                                }
                            }
                        }
                    }
                }
            }
            for child in entity.children { visit(child, ancestorsEnabled: enabled, detail: detail) }
        }
        visit(root, ancestorsEnabled: true, detail: nil)
        count["distinctRetainedMeshResources"] = currentMeshes.count
        return count
    }

    private func loadCounts() -> [String: Int] {
        ["farPalettes": ReplayFarAthletePaletteProvider.preparedPaletteCount,
         "farTextures": ReplayFarAthletePaletteProvider.cachedTextureCount,
         "farPaletteAttempts": ReplayFarAthletePaletteProvider.preparationAttemptCount,
         "farFaceAttempts": ReplayFarAthleteHeadProvider.preparationAttemptCount,
         "farFaceMeshLoads": ReplayFarAthleteHeadProvider.meshLoadCount,
         "articulatedFarPreparations": ReplayArticulatedFarProvider.preparationCount,
         "articulatedKitPreparations": ReplayArticulatedFarKitProvider.preparationCount,
         "articulatedKitTextureLoads": ReplayArticulatedFarKitProvider.textureLoadCount]
    }

    private func update(_ root: Entity, _ scenario: ReplayScenario, _ view: ReplayViewMode,
                        time: Double, playerDetail: ReplayPlayerDetail) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil, playerDetail: playerDetail)
    }
}
