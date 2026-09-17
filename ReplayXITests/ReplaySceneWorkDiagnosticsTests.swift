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
