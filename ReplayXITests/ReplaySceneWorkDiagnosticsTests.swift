import Dispatch
import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Native CPU diagnostics only. No renderer is attached and no elapsed-time
/// threshold is asserted; these results are not a headset frame budget or FPS.
@MainActor
final class ReplaySceneWorkDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetPreparedTestState()
    }

    override func tearDown() {
        resetPreparedTestState()
        super.tearDown()
    }

    private func resetPreparedTestState() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
    }

    func testRecordsFullSquadSceneCPUAcrossViewsAndReversePlayback() throws {
        try recordFullSquad(lowDetail: false)
    }

    func testRecordsMixedSkinSceneCPUWithoutExtraNearQueryRigs() throws {
        try recordFullSquad(lowDetail: true)
    }

    func testRecordsRoomReadyMixedSkinsAndStaticFacesWithoutHotPathLoads() throws {
        try recordFullSquad(lowDetail: true, farFaces: true)
    }

    func testUnchangedLensStylesDoNotRewriteMaterialsOnPlaybackFrames() throws {
        let laneScenario = try XCTUnwrap(DemoScenarios.scenario(for: .passingChannels))
        let laneRoot = PitchSceneFactory.makeMatchRoot(for: laneScenario)
        defer { for child in Array(laneRoot.children) { child.removeFromParent() } }
        func updateLanes() {
            PitchSceneFactory.update(root: laneRoot, scenario: laneScenario, time: 10,
                viewMode: .tacticalTable, perspectiveID: laneScenario.defaultPerspectiveID,
                marks: [], showsLaneLens: true, isDrawing: false,
                positionalOriginTransform: nil)
        }
        updateLanes()
        let firstLaneWrites = PitchSceneFactory.presentationMaterialDiagnostics(for: laneRoot).laneWrites
        XCTAssertEqual(firstLaneWrites, 3)
        for _ in 0..<12 { updateLanes() }
        XCTAssertEqual(PitchSceneFactory.presentationMaterialDiagnostics(for: laneRoot).laneWrites,
                       firstLaneWrites)

        let shapeScenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let shapeRoot = PitchSceneFactory.makeMatchRoot(for: shapeScenario)
        defer { for child in Array(shapeRoot.children) { child.removeFromParent() } }
        func updateShape(ideal: Bool) {
            PitchSceneFactory.update(root: shapeRoot, scenario: shapeScenario, time: 10,
                viewMode: .positional, perspectiveID: shapeScenario.defaultPerspectiveID,
                marks: [], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, showsIdealBranch: ideal)
        }
        updateShape(ideal: false)
        XCTAssertEqual(PitchSceneFactory.presentationMaterialDiagnostics(for: shapeRoot).triangleWrites, 6)
        for _ in 0..<12 { updateShape(ideal: false) }
        XCTAssertEqual(PitchSceneFactory.presentationMaterialDiagnostics(for: shapeRoot).triangleWrites, 6)
        updateShape(ideal: true)
        XCTAssertEqual(PitchSceneFactory.presentationMaterialDiagnostics(for: shapeRoot).triangleWrites, 12)
        updateShape(ideal: true)
        XCTAssertEqual(PitchSceneFactory.presentationMaterialDiagnostics(for: shapeRoot).triangleWrites, 12)
    }

    func testRecordsAllFiveNativeReferenceScenesAcrossViewsForwardReverseAndPaused() async throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled,
                      "Measures the default current-asset path, not the opt-in legacy pilot")
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer {
            ReplayArticulatedFarKitProvider.resetForTesting()
            ReplayArticulatedFarProvider.resetForTesting()
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        for scenario in FootballReferenceScenarios.all {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            // Native preparation is explicit and outside all update timings.
            // Never let another test's cache decide which ball path is timed.
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertEqual(recording.touches.count, plan.count, scenario.id)
            try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
            let regular = (0...48).map { scenario.duration * Double($0) / 48 }
            let contactTimes = recording.touches.flatMap { [$0.time - 0.06, $0.time, $0.time + 0.06] }
            let samples = regular + contactTimes + scenario.moments.map(\.time)
            let forward = Array(Set(samples.map { min(max($0, 0), scenario.duration) })).sorted()
            XCTAssertLessThanOrEqual(forward.count, 120)
            guard forward.count <= 120 else { throw CocoaError(.fileReadTooLarge) }
            let pausedTime = recording.touches.last?.time ?? scenario.duration * 0.5
            var views: [[String: Any]] = []
            for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
                views.append(try diagnoseNativeReference(scenario: scenario, recording: recording,
                    view: view, forward: forward, pausedTime: pausedTime))
            }
            let report: [String: Any] = [
                "scope": "Native test-process CPU: PitchSceneFactory.update on current referenced scenes; record compiler flags separately",
                "includes": "Native ball/contact playback, 22 player tracks, procedural articulation, current near/low skins and far assets, annotations/labels, existing DEBUG counters and ordinary LOD transitions",
                "excludes": "Native physics bake, asset prewarm, initial graph/warmup, assertions/oracles/census, renderer/GPU/compositor, SwiftUI/input and headset work",
                "notFPS": true, "notPacedPlayback": true, "notColdStart": true,
                "scenarioID": scenario.id, "playerIDs": scenario.players.map(\.id),
                "perspectiveID": scenario.defaultPerspectiveID, "authoredMarkCount": scenario.coachMarks.count,
                "nativeStepCount": recording.nativeStepCount, "plannedTouches": plan.count,
                "actualTouches": recording.touches.count, "missedTouches": recording.missedTouchCount,
                "skinCap": ReplaySkinnedAthleteProvider.maximumConcurrentInstances,
                "firstPersonSkinCap": PitchSceneFactory.firstPersonDetailedRigLimit,
                "resourceCountScope": "Separate untimed pass; enabled hierarchy counts, not frustum visibility/draw calls/GPU memory",
                "determinismScope": "Exact player anchors, ball and same-time visible rig/joint/jersey state; reverse compares common visible variants because LOD membership intentionally has hysteresis",
                "views": views
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "ReplayXI-NativeScene141-\(scenario.id).json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private struct NativeEntityState: Equatable {
        let transform: Transform
        let joints: [Transform]
    }

    private struct NativeSceneState: Equatable {
        let presentation: Transform
        let anchors: [Transform]
        let ball: Transform
        let visibleRigNodes: [String: NativeEntityState]
    }

    private func diagnoseNativeReference(scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                                         view: ReplayViewMode, forward: [Double], pausedTime: Double) throws -> [String: Any] {
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        let phases: [(String, [Double])] = [
            ("forward", forward), ("reverse", Array(forward.reversed())),
            ("paused", Array(repeating: pausedTime, count: 60))
        ]
        var phaseReports: [[String: Any]] = []
        for (name, times) in phases {
            let start = try XCTUnwrap(times.first)
            for _ in 0..<3 { update(root, scenario: scenario, view: view, time: start) }
            let loadsBefore = nativeReferenceLoadCounts()
            let playerBefore = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
            let bindingsBefore = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
            let poseWorkBefore = PitchSceneFactory.proceduralPoseWork(for: root)
            ReplayAthleteMotion.resetBallActionSampleCountForTesting()
            PitchSceneFactory.resetAnnotationSceneWorkForTesting()
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            var elapsed: [UInt64] = []
            elapsed.reserveCapacity(times.count)
            for time in times {
                let started = DispatchTime.now().uptimeNanoseconds
                update(root, scenario: scenario, view: view, time: time)
                elapsed.append(DispatchTime.now().uptimeNanoseconds &- started)
            }
            // No assertion, pose readback, resource walk or callback ran inside
            // the timed interval. Read existing counters once per phase.
            let loadsAfter = nativeReferenceLoadCounts()
            let playerAfter = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
            let bindingsAfter = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
            let poseWorkAfter = PitchSceneFactory.proceduralPoseWork(for: root)
            let annotation = PitchSceneFactory.annotationSceneWork
            let inferredActionSamples = ReplayAthleteMotion.ballActionSampleCount
            XCTAssertEqual(loadsAfter, loadsBefore)
            XCTAssertEqual(playerAfter.indexedPlayers, scenario.players.count)
            XCTAssertEqual(playerAfter.entityIndexBuilds, playerBefore.entityIndexBuilds)
            XCTAssertEqual(playerAfter.poseRefreshes - playerBefore.poseRefreshes, times.count)
            XCTAssertEqual(inferredActionSamples, 0, "Explicit native contacts must not infer legacy touches again")
            XCTAssertEqual(annotation.syncCalls, times.count)
            XCTAssertEqual(annotation.markTreeBuilds, 0)
            XCTAssertLessThanOrEqual(bindingsAfter.cachedBindings, 24)
            if name == "paused" {
                XCTAssertEqual(bindingsAfter.hierarchyResolutions, bindingsBefore.hierarchyResolutions)
                XCTAssertEqual(bindingsAfter.invalidations, bindingsBefore.invalidations)
            }
            let sorted = elapsed.sorted()
            let middle = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2)
                ? (Double(sorted[middle - 1]) + Double(sorted[middle])) * 0.5 : Double(sorted[middle])
            let p95 = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
            phaseReports.append([
                "phase": name, "updates": times.count, "sampleTimesSeconds": times,
                "rawUpdateNanoseconds": elapsed, "medianUpdateNanoseconds": median,
                "p95UpdateNanoseconds": sorted[p95], "maximumUpdateNanoseconds": sorted.last!,
                "loadsBefore": loadsBefore, "loadsAfter": loadsAfter,
                "playerIndexBuilds": playerAfter.entityIndexBuilds - playerBefore.entityIndexBuilds,
                "poseRefreshes": playerAfter.poseRefreshes - playerBefore.poseRefreshes,
                "bindingHierarchyResolutions": bindingsAfter.hierarchyResolutions - bindingsBefore.hierarchyResolutions,
                "bindingInvalidations": bindingsAfter.invalidations - bindingsBefore.invalidations,
                "proceduralPoseEvaluations": poseWorkAfter.evaluations - poseWorkBefore.evaluations,
                "proceduralPoseCacheHits": poseWorkAfter.cacheHits - poseWorkBefore.cacheHits,
                "inferredBallActionSamples": inferredActionSamples,
                "annotationSyncs": annotation.syncCalls, "annotationTreeBuilds": annotation.markTreeBuilds,
                "proceduralVisibilityNodeVisits": PitchSceneFactory.proceduralVisibilityNodeVisits,
                "proceduralVisibilityWrites": PitchSceneFactory.proceduralVisibilityModelWrites
            ])
        }

        var reference: [Double: NativeSceneState] = [:]
        var resources: [[String: Int]] = []
        var skinMeshes: [ObjectIdentifier: MeshResource] = [:]
        var jointPaths: [String: Int] = [:]
        var pathsOutsideSkin = Set<String>()
        var comparedReverseNodes = 0
        let expectedSkins = view == .firstPerson ? PitchSceneFactory.firstPersonDetailedRigLimit
            : ReplaySkinnedAthleteProvider.maximumConcurrentInstances
        let untimedLoads = nativeReferenceLoadCounts()
        for (phase, times) in phases {
            for time in times {
                update(root, scenario: scenario, view: view, time: time)
                let state = try nativeReferenceState(root, scenario: scenario)
                update(root, scenario: scenario, view: view, time: time)
                XCTAssertEqual(try nativeReferenceState(root, scenario: scenario), state,
                               "Exact repeat at \(scenario.id)/\(view.rawValue)/\(time)")
                if let previous = reference[time] {
                    XCTAssertEqual(state.presentation, previous.presentation)
                    XCTAssertEqual(state.anchors, previous.anchors)
                    XCTAssertEqual(state.ball, previous.ball)
                    for (path, actual) in state.visibleRigNodes {
                        if let expected = previous.visibleRigNodes[path] {
                            XCTAssertEqual(actual, expected, "Same rendered variant at \(time): \(path)")
                            if phase == "reverse" { comparedReverseNodes += 1 }
                        }
                    }
                } else { reference[time] = state }
                let counts = resourceCounts(in: root, skinMeshes: &skinMeshes,
                    jointModelPaths: &jointPaths, jointModelPathsOutsideSkin: &pathsOutsideSkin)
                resources.append(counts)
                XCTAssertEqual(counts["retainedSkinRoots"], expectedSkins)
                XCTAssertEqual(counts["enabledSkinRoots"], expectedSkins)
                XCTAssertEqual(counts["retainedFarRigs"], scenario.players.count)
                XCTAssertEqual(counts["enabledFarRigs"], scenario.players.count - expectedSkins - (view == .firstPerson ? 1 : 0))
                XCTAssertLessThanOrEqual(try XCTUnwrap(counts["retainedNearRigs"]), 2)
            }
        }
        XCTAssertEqual(nativeReferenceLoadCounts(), untimedLoads)
        XCTAssertGreaterThan(comparedReverseNodes, 0)
        XCTAssertEqual(skinMeshes.count, view == .firstPerson ? 1 : 2)
        // The current far asset deliberately has four three-joint limb skins
        // per player. The legacy static-far diagnostic's zero-skeleton rule
        // does not apply, but no other skeleton outside admitted skins is valid.
        let limbPaths = [
            "body-root/hips/left-hip/left-leg", "body-root/hips/right-hip/right-leg",
            "body-root/hips/spine/left-shoulder/left-arm", "body-root/hips/spine/right-shoulder/right-arm"
        ]
        let expectedFarJointPaths = Set(scenario.players.flatMap { player in
            limbPaths.map { "/\(root.name)/players-root/player-\(player.id)/table-marker/\($0)" }
        })
        XCTAssertEqual(pathsOutsideSkin, expectedFarJointPaths,
                       "Exactly four admitted far limbs per player; no unexpected or missing skeletons")
        for path in expectedFarJointPaths {
            XCTAssertEqual(jointPaths[path], 3, "Far limbs must not acquire full-body skeletons: \(path)")
            var entity: Entity? = root
            for name in path.split(separator: "/").dropFirst() {
                entity = entity?.children.first { $0.name == String(name) }
            }
            let model = try XCTUnwrap(entity as? ModelEntity)
            XCTAssertEqual(model.jointNames, ["Root", "Root/Bend", "Root/Bend/Tip"])
            XCTAssertEqual(model.jointTransforms.count, 3)
        }
        var ranges: [String: [Int]] = [:]
        for key in try XCTUnwrap(resources.first).keys {
            let values = resources.compactMap { $0[key] }
            ranges[key] = [try XCTUnwrap(values.min()), try XCTUnwrap(values.max())]
        }
        return ["view": view.rawValue, "phases": phaseReports, "resourceMinMax": ranges,
                "retainedSharedSkinMeshes": skinMeshes.count, "jointModelPathsAndCounts": jointPaths,
                "jointModelPathsOutsideAdmittedSkin": pathsOutsideSkin.sorted(),
                "expectedArticulatedFarJointModels": expectedFarJointPaths.count,
                "unexpectedJointModelPathsOutsideAdmittedSkin": pathsOutsideSkin.subtracting(expectedFarJointPaths).sorted(),
                "exactReverseVisibleNodeComparisons": comparedReverseNodes,
                "untimedVerificationUpdates": phases.reduce(0) { $0 + $1.1.count * 2 }]
    }

    private func nativeReferenceState(_ root: Entity, scenario: ReplayScenario) throws -> NativeSceneState {
        let playersRoot = try XCTUnwrap(root.findEntity(named: "players-root"))
        var anchors: [Transform] = []
        var nodes: [String: NativeEntityState] = [:]
        @discardableResult
        func visit(_ entity: Entity, path: String) -> Bool {
            guard entity.isEnabled else { return false }
            var variant = path
            if entity.name == ReplaySkinnedAthleteProvider.visualRootName,
               let model = ReplaySkinnedAthleteProvider.skinnedModels(in: entity).first,
               let component = model.model {
                // Near and low share names/skeletons but have different floor
                // envelopes. Do not compare those intentionally different LODs.
                let vertices = component.mesh.contents.models.reduce(0) { count, mesh in
                    count + mesh.parts.reduce(0) { $0 + $1.positions.count }
                }
                variant += "#vertices-\(vertices)"
            }
            var hasVisibleModel = entity.components[ModelComponent.self] != nil
            var occurrences: [String: Int] = [:]
            for child in entity.children {
                let ordinal = occurrences[child.name, default: 0]
                occurrences[child.name] = ordinal + 1
                hasVisibleModel = visit(child, path: variant + "/" + child.name + "[\(ordinal)]") || hasVisibleModel
            }
            // Procedural query joints intentionally stop animating while their
            // meshes are hidden behind a skin. Compare rendered hierarchies,
            // not stale invisible fallback/query bodies.
            if hasVisibleModel {
                nodes[variant] = NativeEntityState(transform: entity.transform,
                                                   joints: (entity as? ModelEntity)?.jointTransforms ?? [])
            }
            return hasVisibleModel
        }
        for player in scenario.players {
            let entity = try XCTUnwrap(playersRoot.children.first { $0.name == "player-\(player.id)" })
            anchors.append(entity.transform)
            visit(entity, path: player.id)
        }
        return NativeSceneState(presentation: root.transform, anchors: anchors,
                                ball: try XCTUnwrap(root.findEntity(named: "ball")).transform,
                                visibleRigNodes: nodes)
    }

    private func nativeReferenceLoadCounts() -> [String: Int] {
        ["farPalettes": ReplayFarAthletePaletteProvider.preparedPaletteCount,
         "farTextures": ReplayFarAthletePaletteProvider.cachedTextureCount,
         "farPaletteAttempts": ReplayFarAthletePaletteProvider.preparationAttemptCount,
         "farFaceAttempts": ReplayFarAthleteHeadProvider.preparationAttemptCount,
         "farFaceMeshLoads": ReplayFarAthleteHeadProvider.meshLoadCount,
         "articulatedFarPreparations": ReplayArticulatedFarProvider.preparationCount,
         "articulatedKitPreparations": ReplayArticulatedFarKitProvider.preparationCount,
         "articulatedKitTextureLoads": ReplayArticulatedFarKitProvider.textureLoadCount,
         "articulatedKitTextures": ReplayArticulatedFarKitProvider.cachedTextureCount]
    }

    private func recordFullSquad(lowDetail: Bool, farFaces: Bool = false) throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled,
                      "This baseline measures default admission, not the opt-in imported pilot")
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertEqual(scenario.players.count, 22)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)

        // Match the room's cold-path preparation, without including it in the
        // update timing. Immutable mesh/pitch caches may already be warm from
        // another test, so this deliberately reports no cold-start benchmark.
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        try ReplaySkinnedAthleteProvider.prewarm()
        if lowDetail { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        if farFaces { try ReplayFarAthleteHeadProvider.prewarm() }
        try ReplayStrategyBallProvider.prewarm()
        try ReplayStrategyPitchProvider.prewarm()
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        let preparedPaletteCount = ReplayFarAthletePaletteProvider.preparedPaletteCount
        let preparedTextureCount = ReplayFarAthletePaletteProvider.cachedTextureCount
        let palettePreparationAttempts = ReplayFarAthletePaletteProvider.preparationAttemptCount
        let facePreparationAttempts = ReplayFarAthleteHeadProvider.preparationAttemptCount
        let faceMeshLoads = ReplayFarAthleteHeadProvider.meshLoadCount
        XCTAssertEqual(faceMeshLoads, farFaces ? 1 : 0)

        // Half-second samples span the complete authored move. Exact cue times
        // also cover receive/overlap/cut-back boundaries, then the same path is
        // traversed backwards. This is sampled seek work, not paced 30 Hz play.
        let regularTimes = (0...64).map { scenario.duration * Double($0) / 64 }
        let forwardTimes = Array(Set(regularTimes + scenario.moments.map(\.time))).sorted()
        let times = forwardTimes + forwardTimes.reversed()
        var views: [[String: Any]] = []
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            views.append(try diagnose(scenario: scenario, view: view, times: times, lowDetail: lowDetail))
        }

        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparedPaletteCount, preparedPaletteCount)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedTextureCount, preparedTextureCount)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, palettePreparationAttempts,
                       "Steady scene updates must not prepare new far textures")
        XCTAssertEqual(ReplayFarAthleteHeadProvider.preparationAttemptCount, facePreparationAttempts)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, faceMeshLoads,
                       "Static faces must not load an asset during playback or view transitions")
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
        let report: [String: Any] = [
            "scope": "Native test-process CPU: PitchSceneFactory.update only",
            "excludes": "prewarm, initial scene build, warm-up, count walks, assertions, rendering, GPU, compositor, head tracking, SwiftUI and input",
            "includes": "track and ball sampling, near/far articulation, admitted skins, annotation/label updates, existing diagnostic instrumentation and ordinary POV neighbour transitions",
            "notFPS": true,
            "notColdStart": true,
            "notPacedPlayback": true,
            "scenarioID": scenario.id,
            "playerCount": scenario.players.count,
            "authoredMarkCount": scenario.coachMarks.count,
            "perspectiveID": scenario.defaultPerspectiveID,
            "impactCue": false,
            "laneLens": false,
            "skinCap": ReplaySkinnedAthleteProvider.maximumConcurrentInstances,
            "lowDetailAdmission": lowDetail,
            "staticFarFaces": farFaces,
            "firstPersonSkinCap": PitchSceneFactory.firstPersonDetailedRigLimit,
            "preparedFarPalettes": preparedPaletteCount,
            "preparedFarTextures": preparedTextureCount,
            "skinDecodedBaseTextureBytesNotTotalMemory": ReplaySkinnedAthleteProvider.decodedTextureBytes,
            "resourceCountScope": "Separate untimed replay; enabled means hierarchy flags, not frustum visibility or actual draw calls",
            "views": views
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = farFaces ? "ReplayXI-Scene116-FacesCPUWork.json"
            : (lowDetail ? "ReplayXI-Scene113-MixedCPUWork.json" : "ReplayXI-Scene107-CPUWork.json")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func diagnose(scenario: ReplayScenario, view: ReplayViewMode,
                          times: [Double], lowDetail: Bool) throws -> [String: Any] {
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        // Each view owns a fresh graph. Do not leave this diagnostic's graph
        // attached while another view/provider lifecycle is prepared.
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let firstTime = try XCTUnwrap(times.first)
        for _ in 0..<3 { update(root, scenario: scenario, view: view, time: firstTime) }
        let playerIndexBefore = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        let bindingsBefore = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()

        var elapsed: [Double] = []
        elapsed.reserveCapacity(times.count)
        for time in times {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            update(root, scenario: scenario, view: view, time: time)
            let nanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            elapsed.append(Double(nanoseconds) / 1_000_000)
        }
        // All assertions, snapshots and recursive graph walks are outside the
        // timed loop. The timed work may legitimately replace a POV neighbour;
        // only initial construction/preparation is excluded.
        let playerIndexAfter = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        let bindingsAfter = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        let actionSamples = ReplayAthleteMotion.ballActionSampleCount
        let annotationWork = PitchSceneFactory.annotationSceneWork
        let visibilityVisits = PitchSceneFactory.proceduralVisibilityNodeVisits
        let visibilityWrites = PitchSceneFactory.proceduralVisibilityModelWrites
        XCTAssertEqual(playerIndexAfter.indexedPlayers, 22)
        XCTAssertEqual(playerIndexAfter.entityIndexBuilds, playerIndexBefore.entityIndexBuilds)
        XCTAssertEqual(playerIndexAfter.poseRefreshes - playerIndexBefore.poseRefreshes, times.count)
        XCTAssertEqual(bindingsAfter.hierarchyResolutions, bindingsBefore.hierarchyResolutions)
        XCTAssertLessThanOrEqual(bindingsAfter.cachedBindings, 24)
        XCTAssertEqual(actionSamples, times.count * scenario.players.count)
        XCTAssertEqual(annotationWork.syncCalls, times.count)
        XCTAssertEqual(annotationWork.markTreeBuilds, 0)
        XCTAssertEqual(elapsed.count, times.count)
        XCTAssertTrue(elapsed.allSatisfy { $0.isFinite && $0 >= 0 })

        var resources: [[String: Int]] = []
        // Keep the compared resources alive, as the provider's clone-sharing
        // test does. Bare ObjectIdentifiers cannot establish native resource
        // growth when a getter's Swift wrapper may have been released.
        var skinMeshes: [ObjectIdentifier: MeshResource] = [:]
        var jointModelPaths: [String: Int] = [:]
        var jointModelPathsOutsideSkin = Set<String>()
        let expectedNear = view == .firstPerson ? PitchSceneFactory.firstPersonDetailedRigLimit : 1
        let expectsMixed = lowDetail && view != .firstPerson
        let expectedSkins = expectsMixed ? ReplaySkinnedAthleteProvider.maximumConcurrentInstances : expectedNear
        for time in times {
            update(root, scenario: scenario, view: view, time: time)
            let counts = resourceCounts(in: root, skinMeshes: &skinMeshes,
                                        jointModelPaths: &jointModelPaths,
                                        jointModelPathsOutsideSkin: &jointModelPathsOutsideSkin)
            resources.append(counts)
            XCTAssertEqual(counts["retainedSkinRoots"], expectedSkins)
            XCTAssertEqual(counts["enabledSkinRoots"], expectedSkins)
            XCTAssertEqual(counts["retainedFarRigs"], 22)
            XCTAssertEqual(counts["enabledFarRigs"], 22 - expectedSkins - (view == .firstPerson ? 1 : 0))
            XCTAssertEqual(counts["retainedNearRigs"], expectedNear,
                           "Low skins must not allocate extra procedural near/query rigs")
            XCTAssertLessThanOrEqual(try XCTUnwrap(counts["retainedSkinRoots"]),
                                     ReplaySkinnedAthleteProvider.maximumConcurrentInstances)
        }
        XCTAssertEqual(skinMeshes.count, expectsMixed ? 2 : 1,
                       "Each detail level must share one prepared mesh")
        let keys = try XCTUnwrap(resources.first).keys.sorted()
        var resourceRanges: [String: [Int]] = [:]
        for key in keys {
            let values = resources.compactMap { $0[key] }
            resourceRanges[key] = [try XCTUnwrap(values.min()), try XCTUnwrap(values.max())]
        }
        let sorted = elapsed.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        let p95Index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return [
            "view": view.rawValue,
            "measuredUpdates": times.count,
            "sampleTimesSeconds": times,
            "medianUpdateMilliseconds": median,
            "p95UpdateMilliseconds": sorted[p95Index],
            "maximumUpdateMilliseconds": try XCTUnwrap(sorted.last),
            "resourceMinMax": resourceRanges,
            "skinMeshIdentitiesAcrossUntimedPass": skinMeshes.count,
            "skinMeshReferencesRetainedDuringUntimedPass": true,
            "jointModelPathsAndCounts": jointModelPaths,
            "jointModelPathsOutsideAdmittedSkin": jointModelPathsOutsideSkin.sorted(),
            "playerIndexBuildsDuringTiming": playerIndexAfter.entityIndexBuilds - playerIndexBefore.entityIndexBuilds,
            "poseRefreshesDuringTiming": playerIndexAfter.poseRefreshes - playerIndexBefore.poseRefreshes,
            "bindingHierarchyResolutionsDuringTiming": bindingsAfter.hierarchyResolutions - bindingsBefore.hierarchyResolutions,
            "bindingInvalidationsDuringTiming": bindingsAfter.invalidations - bindingsBefore.invalidations,
            "ballActionSamplesDuringTiming": actionSamples,
            "annotationSyncsDuringTiming": annotationWork.syncCalls,
            "annotationTreeBuildsDuringTiming": annotationWork.markTreeBuilds,
            "visibilityNodeVisitsDuringTiming": visibilityVisits,
            "visibilityModelWritesDuringTiming": visibilityWrites
        ]
    }

    private func resourceCounts(in root: Entity,
                                skinMeshes: inout [ObjectIdentifier: MeshResource],
                                jointModelPaths: inout [String: Int],
                                jointModelPathsOutsideSkin: inout Set<String>) -> [String: Int] {
        var counts = ["residentEntities": 0, "retainedModels": 0, "enabledModels": 0,
                      "enabledMaterialSlots": 0, "retainedSkinRoots": 0, "enabledSkinRoots": 0,
                      "retainedNearRigs": 0, "retainedFarRigs": 0, "enabledFarRigs": 0]
        var meshes: [ObjectIdentifier: MeshResource] = [:]
        func visit(_ entity: Entity, ancestorsEnabled: Bool, insideSkin: Bool, path: String) {
            counts["residentEntities", default: 0] += 1
            let enabled = ancestorsEnabled && entity.isEnabled
            let isSkin = insideSkin || entity.name == ReplaySkinnedAthleteProvider.visualRootName
            let entityPath = path + "/" + entity.name
            if let component = entity.components[ModelComponent.self] {
                counts["retainedModels", default: 0] += 1
                let mesh = component.mesh
                meshes[ObjectIdentifier(mesh)] = mesh
                if enabled {
                    counts["enabledModels", default: 0] += 1
                    counts["enabledMaterialSlots", default: 0] += component.materials.count
                }
                if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
                    jointModelPaths[entityPath] = model.jointNames.count
                    if isSkin {
                        skinMeshes[ObjectIdentifier(mesh)] = mesh
                    } else {
                        jointModelPathsOutsideSkin.insert(entityPath)
                    }
                }
            }
            if entity.name == ReplaySkinnedAthleteProvider.visualRootName {
                counts["retainedSkinRoots", default: 0] += 1
                if enabled { counts["enabledSkinRoots", default: 0] += 1 }
            }
            if entity.name == "full-rig" { counts["retainedNearRigs", default: 0] += 1 }
            if entity.name == "table-marker" {
                counts["retainedFarRigs", default: 0] += 1
                if enabled { counts["enabledFarRigs", default: 0] += 1 }
            }
            for child in entity.children {
                visit(child, ancestorsEnabled: enabled, insideSkin: isSkin, path: entityPath)
            }
        }
        visit(root, ancestorsEnabled: true, insideSkin: false, path: "")
        counts["distinctRetainedMeshResources"] = meshes.count
        return counts
    }

    private func update(_ root: Entity, scenario: ReplayScenario, view: ReplayViewMode, time: Double) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }
}
