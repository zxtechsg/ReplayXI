import Dispatch
import RealityKit
import XCTest
@testable import ReplayXI

/// Work counts, retained resources and instrumented elapsed time—not headset
/// FPS, allocation bytes or a performance threshold. The saved library is
/// memory-only and every mark is created/restored through the actual Store.
@MainActor
final class ReplayAnnotationSceneWorkDiagnosticsTests: XCTestCase {
    func testSixteenSavedMarksAcrossColdLoadSteadyPlaybackAndEndpointPreview() throws {
        try diagnose(markCount: 16)
    }

    func testSixtyFourSavedMarksAcrossColdLoadSteadyPlaybackAndEndpointPreview() throws {
        try diagnose(markCount: 64)
    }

    func testMaximumSavedMarksRejectOverflowAndKeepEndpointWorkBounded() throws {
        XCTAssertEqual(ReplayStore.maximumSharedCoachMarks, 128)
        try diagnose(markCount: ReplayStore.maximumSharedCoachMarks)
    }

    private struct ResourceCounts: Codable {
        let markRoots: Int
        let enabledMarkRoots: Int
        let residentEntities: Int
        let residentModels: Int
        let enabledModels: Int
        let retainedAnnotationGlyphResources: Int
        let sharedTextCacheEntries: Int
    }

    private struct Phase: Codable {
        let name: String
        let updateCount: Int
        let sceneElapsedNanoseconds: UInt64
        let work: PitchSceneFactory.AnnotationSceneWorkCounters
        let resources: ResourceCounts
    }

    private struct Diagnostic: Codable {
        let totalMarks: Int
        let authoredMarks: Int
        let phases: [Phase]
        let qualification: String
    }

    private func diagnose(markCount: Int) throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let scenario = store.selectedScenario
        XCTAssertEqual(scenario.kind, .squadReplay)
        XCTAssertEqual(store.viewMode, .tacticalTable)
        let authoredCount = scenario.coachMarks.count
        XCTAssertGreaterThan(markCount, authoredCount)
        store.seek(to: 24, broadcast: false)
        var userIDs: [UUID] = []
        for index in 0..<(markCount - authoredCount) {
            // This quiet corner is away from both sides at 24 s. Unbound marks
            // isolate semantic revision work from legitimate tracking work.
            let start = PitchPoint(
                x: -32 + Float(index % 8) * 0.4,
                z: -45 + Float(index / 8) * 0.4
            )
            store.beginDrawing(.run)
            XCTAssertNil(store.registerPitchTap(start))
            let mark = try XCTUnwrap(store.registerPitchTap(
                PitchPoint(x: start.x + 2, z: start.z + 4)
            ))
            XCTAssertFalse(mark.followsPlayerTracks)
            XCTAssertTrue(store.updateCoachMarkLabel(
                id: mark.id,
                label: String(format: "M%02d future run", index)
            ))
            userIDs.append(mark.id)
        }
        XCTAssertEqual(store.marks.count, markCount)
        XCTAssertTrue(store.marks.allSatisfy { !$0.followsPlayerTracks })
        if markCount == ReplayStore.maximumSharedCoachMarks {
            let fullHistory = store.marks
            store.beginDrawing(.run)
            XCTAssertFalse(store.isDrawing)
            XCTAssertNil(store.pendingDrawStart)
            XCTAssertNil(store.registerPitchTap(PitchPoint(x: -30, z: -44)))
            XCTAssertEqual(store.marks, fullHistory,
                           "Refusing a new mark must preserve the entire saved history")
        }
        store.seek(to: 0, broadcast: false)
        let savedMarks = store.marks
        XCTAssertTrue(store.saveReview(named: "Loop 93 \(markCount) marks"))
        let saved = try XCTUnwrap(store.savedReviews.first)
        let other = try XCTUnwrap(store.scenarios.first { $0.id != scenario.id })
        store.selectScenario(id: other.id, broadcast: false)
        XCTAssertTrue(store.restoreReview(saved))
        XCTAssertEqual(store.marks, savedMarks)
        XCTAssertEqual(store.playhead, 0)
        XCTAssertFalse(store.hasAnnotationEditHistory)

        // Match-root construction installs only its bundled authored marks.
        // Reset afterwards so cold-load work measures applying the saved marks.
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let marksRoot = try XCTUnwrap(root.findEntity(named: "marks-root"))
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        var startedAt = DispatchTime.now().uptimeNanoseconds
        update(root, from: store)
        let coldElapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
        let coldWork = PitchSceneFactory.annotationSceneWork
        XCTAssertEqual(coldWork.syncCalls, 1)
        XCTAssertEqual(coldWork.semanticRevisions, 1)
        XCTAssertEqual(coldWork.markTreeBuilds, markCount - authoredCount)
        XCTAssertEqual(coldWork.trackedGeometryUpdates, 0)
        let coldResources = resources(in: marksRoot)
        XCTAssertEqual(coldResources.markRoots, markCount)
        XCTAssertEqual(coldResources.enabledMarkRoots, 0)
        XCTAssertEqual(coldResources.enabledModels, 0)
        XCTAssertEqual(coldResources.retainedAnnotationGlyphResources, markCount)
        var phases = [Phase(
            name: "cold_saved_review_at_0s",
            updateCount: 1,
            sceneElapsedNanoseconds: coldElapsed,
            work: coldWork,
            resources: coldResources
        )]
        let retainedRoots = try store.marks.map { mark in
            try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        }

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        startedAt = DispatchTime.now().uptimeNanoseconds
        for frame in 1...60 {
            store.seek(to: Double(frame) / 60, broadcast: false)
            update(root, from: store)
        }
        let steadyElapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
        let steadyWork = PitchSceneFactory.annotationSceneWork
        XCTAssertEqual(steadyWork.syncCalls, 60)
        XCTAssertEqual(steadyWork.semanticRevisions, 0)
        XCTAssertEqual(steadyWork.markTreeBuilds, 0)
        XCTAssertEqual(steadyWork.revisionGeometryUpdates, 0)
        XCTAssertEqual(steadyWork.trackedGeometryUpdates, 0)
        phases.append(Phase(
            name: "60_unchanged_playback_frames_0_to_1s",
            updateCount: 60,
            sceneElapsedNanoseconds: steadyElapsed,
            work: steadyWork,
            resources: resources(in: marksRoot)
        ))
        assertRetainedRoots(retainedRoots, match: store.marks, in: root)

        let selectedID = try XCTUnwrap(userIDs.first)
        store.seek(to: 24, broadcast: false)
        update(root, from: store, selectedID: selectedID)
        let previewBaseline = store.marks
        let baselineMark = try XCTUnwrap(previewBaseline.first { $0.id == selectedID })
        let selectedRoot = try XCTUnwrap(root.findEntity(named: "mark-\(selectedID.uuidString)"))
        XCTAssertTrue(selectedRoot.isEnabled)
        XCTAssertLessThan(resources(in: marksRoot).enabledMarkRoots, markCount)
        XCTAssertLessThanOrEqual(resources(in: marksRoot).enabledModels,
                                 PlaybackSceneRenderBudget.normalAnnotationDrawLimit)

        let gestureID = UUID()
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        startedAt = DispatchTime.now().uptimeNanoseconds
        for frame in 1...60 {
            XCTAssertNotNil(store.previewCoachMarkEndpoint(
                id: selectedID,
                endpoint: .end,
                gestureID: gestureID,
                cumulativeDelta: PitchPoint(x: Float(frame) / 100, z: 0)
            ))
            update(root, from: store, selectedID: selectedID)
        }
        let previewElapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
        let previewWork = PitchSceneFactory.annotationSceneWork
        XCTAssertEqual(previewWork.syncCalls, 60)
        XCTAssertEqual(previewWork.semanticRevisions, 60)
        XCTAssertEqual(previewWork.markTreeBuilds, 0)
        XCTAssertEqual(previewWork.trackedGeometryUpdates, 0)
        // One changed endpoint per sample must not rewrite the other intact
        // bindings. Resource/tracking correctness is checked independently.
        XCTAssertEqual(previewWork.revisionGeometryUpdates, 60)
        XCTAssertEqual(previewWork.unchangedRevisionGeometryUpdates, 0)
        XCTAssertLessThanOrEqual(resources(in: marksRoot).enabledModels,
                                 PlaybackSceneRenderBudget.normalAnnotationDrawLimit)
        phases.append(Phase(
            name: "60_single_endpoint_preview_samples_at_24s",
            updateCount: 60,
            sceneElapsedNanoseconds: previewElapsed,
            work: previewWork,
            resources: resources(in: marksRoot)
        ))
        assertRetainedRoots(retainedRoots, match: store.marks, in: root)
        let moved = try XCTUnwrap(store.marks.first { $0.id == selectedID })
        XCTAssertEqual(moved.start, baselineMark.start)
        XCTAssertEqual(moved.end.x, baselineMark.end.x + 0.6, accuracy: 0.000_1)
        XCTAssertEqual(moved.end.z, baselineMark.end.z)
        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: selectedID, gestureID: gestureID))
        XCTAssertEqual(store.marks, previewBaseline)
        XCTAssertFalse(store.hasAnnotationEditHistory)
        update(root, from: store, selectedID: selectedID)
        assertRetainedRoots(retainedRoots, match: store.marks, in: root)
        XCTAssertEqual(store.savedReviews.first?.state.marks, savedMarks)
        XCTAssertLessThanOrEqual(
            PlaybackSpatialLabels.cachedTextMeshCount,
            PlaybackSpatialLabels.maximumCachedTextMeshes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let diagnostic = Diagnostic(
            totalMarks: markCount,
            authoredMarks: authoredCount,
            phases: phases,
            qualification: "Simulator work counts and retained resources. Instrumented elapsed time is descriptive, not thread CPU time, allocation bytes, headset FPS or a performance guarantee. Cold phase excludes initial bundled-scene creation."
        )
        let attachment = XCTAttachment(
            data: try encoder.encode(diagnostic),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "ReplayXI-Loop93-AnnotationWork-\(markCount).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ root: Entity, from store: ReplayStore, selectedID: UUID? = nil) {
        PitchSceneFactory.update(
            root: root,
            scenario: store.selectedScenario,
            time: store.playhead,
            viewMode: store.viewMode,
            perspectiveID: store.activePerspectiveID,
            marks: store.marks,
            selectedAnnotationID: selectedID,
            selectedAnnotationIsEditable: selectedID != nil,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
    }

    private func assertRetainedRoots(_ entities: [Entity], match marks: [CoachMark], in root: Entity) {
        XCTAssertEqual(entities.count, marks.count)
        for (entity, mark) in zip(entities, marks) {
            XCTAssertTrue(entity === root.findEntity(named: "mark-\(mark.id.uuidString)"))
        }
    }

    private func resources(in marksRoot: Entity) -> ResourceCounts {
        var entityCount = 0
        var modelCount = 0
        var enabledModelCount = 0
        // Keep Swift resource wrappers alive throughout the walk. Beyond the
        // shared text-cache capacity, a getter may return a short-lived wrapper
        // whose address is then reused; bare IDs undercount distinct glyphs.
        var glyphResources: [ObjectIdentifier: MeshResource] = [:]
        func visit(_ entity: Entity, ancestorsEnabled: Bool) {
            entityCount += 1
            let enabled = ancestorsEnabled && entity.isEnabled
            if let model = entity.components[ModelComponent.self] {
                modelCount += 1
                if enabled { enabledModelCount += 1 }
                if entity.name == "annotation-tag-glyph" {
                    let glyphMesh = model.mesh
                    glyphResources[ObjectIdentifier(glyphMesh)] = glyphMesh
                }
            }
            for child in entity.children {
                visit(child, ancestorsEnabled: enabled)
            }
        }
        for child in marksRoot.children {
            visit(child, ancestorsEnabled: marksRoot.isEnabled)
        }
        return ResourceCounts(
            markRoots: marksRoot.children.count,
            enabledMarkRoots: marksRoot.children.filter { marksRoot.isEnabled && $0.isEnabled }.count,
            residentEntities: entityCount,
            residentModels: modelCount,
            enabledModels: enabledModelCount,
            retainedAnnotationGlyphResources: glyphResources.count,
            sharedTextCacheEntries: PlaybackSpatialLabels.cachedTextMeshCount
        )
    }
}
