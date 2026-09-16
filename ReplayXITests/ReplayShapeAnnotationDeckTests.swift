import XCTest
@testable import ReplayXI

@MainActor
final class ReplayShapeAnnotationDeckTests: XCTestCase {
    func testRestoredPlayerBoundShapeMarkOpensEditorAtItsRecordedMoment() throws {
        for stage in ShapeFocusStage.allCases {
            let store = makeStore(stage: stage)
            let mark = try drawPlayerRun(in: store)
            let geometry = store.presentedCoachMarkGeometry(mark, at: mark.revealTime)
            XCTAssertTrue(store.saveReview(named: "Shape edit route"))
            let review = try XCTUnwrap(store.savedReviews.first)
            store.selectScenario(id: "eleven-eyes", broadcast: false)
            XCTAssertNotEqual(store.selectedScenarioID, "triangle-lock")
            XCTAssertTrue(store.restoreReview(review))

            // This is the same selection/seek state produced by a spatial mark tap.
            store.setPlaying(false, broadcast: false)
            store.seek(to: mark.revealTime, broadcast: false)
            XCTAssertTrue(store.marks.contains(mark))
            XCTAssertEqual(store.playhead, mark.revealTime)
            XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead), geometry)
            XCTAssertEqual(mode(store, hasWorkflow: true), .shapeAnnotations,
                           "A visible selection must expose its shared inspector and Close route")
        }
    }

    func testEmptyAndStartedShapeDraftsExposeTheExistingDrawingAndCancelShelf() {
        for stage in ShapeFocusStage.allCases {
            let store = makeStore(stage: stage)
            let originalTime = store.playhead
            store.beginDrawing(.run)
            XCTAssertTrue(store.isDrawing)
            XCTAssertNil(store.pendingDrawStart)
            XCTAssertEqual(mode(store), .annotationDrawing)

            XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
            XCTAssertNotNil(store.pendingDrawStart)
            XCTAssertEqual(mode(store, hasWorkflow: true), .annotationDrawing,
                           "A stale selected shelf cannot hide the owning draft")
            store.cancelDrawing()
            XCTAssertFalse(store.isDrawing)
            XCTAssertNil(store.pendingDrawStart)
            XCTAssertEqual(store.playhead, originalTime)
            XCTAssertEqual(mode(store), .shapeStatus)
        }
    }

    func testShapeBackAndAnnotationSubmenusStayReachableIncludingEraseUndo() throws {
        let store = makeStore(stage: .ideal)
        let mark = try drawPlayerRun(in: store)
        let panels: [PlaybackInlinePanel] = [
            .annotationDuration(mark.id), .annotationGeometry(mark.id),
            .annotationLabel(mark.id), .annotationTracking(mark.id), .annotationEdit
        ]
        for panel in panels {
            XCTAssertTrue(panel.isAnnotationPanel)
            XCTAssertEqual(mode(store, hasWorkflow: panel.isAnnotationPanel), .shapeAnnotations)
        }
        XCTAssertEqual(mode(store, hasWorkflow: true), .shapeAnnotations,
                       "Back to timeline leaves selection nil but must keep the event shelf visible")
        XCTAssertTrue(store.removeCoachMark(id: mark.id))
        XCTAssertTrue(store.canUndoAnnotationEdit)
        XCTAssertEqual(mode(store, hasWorkflow: PlaybackInlinePanel.annotationEdit.isAnnotationPanel),
                       .shapeAnnotations, "Erase must keep its existing Undo shelf reachable")
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertTrue(store.marks.contains(mark))
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertFalse(store.marks.contains(where: { $0.id == mark.id }))
    }

    func testHeldEndpointAndTimelineKeepTheirShapeEditorMounted() throws {
        let store = makeStore(stage: .problem)
        let mark = try drawPlayerRun(in: store)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id,
            start: geometry.start,
            end: PitchPoint(x: geometry.end.x + 0.25, z: geometry.end.z),
            broadcast: false
        ))
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(store.canChangePlaybackView)
        XCTAssertEqual(mode(store, hasWorkflow: true), .shapeAnnotations)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertTrue(store.canChangePlaybackView)

        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: store.playhead + 0.5))
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertFalse(store.canChangePlaybackView)
        XCTAssertEqual(mode(store, hasWorkflow: true), .shapeAnnotations)
        store.cancelTimelineScrub()
        XCTAssertTrue(store.canChangePlaybackView)
        XCTAssertEqual(store.marks.last, mark)
    }

    func testPhysicalStationsAlwaysPreemptStaleAnnotationRoutes() {
        for isDrawing in [false, true] {
            for hasWorkflow in [false, true] {
                XCTAssertEqual(PlaybackControlDeckPresentation.mode(
                    isPhysicalPlacement: true,
                    isShapeFocus: true,
                    isDrawing: isDrawing,
                    hasAnnotationWorkflow: hasWorkflow
                ), .physicalStations)
            }
        }
        let store = makeStore(stage: .ideal)
        store.activateLocalTrianglePreview(anchorID: UUID())
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertEqual(mode(store, hasWorkflow: true), .physicalStations)
        store.endTrianglePlacement()
        XCTAssertEqual(mode(store), .shapeStatus)
    }

    func testClosingShapeAndNormalMatchControlsKeepTheirExistingModes() {
        let shape = makeStore(stage: .problem)
        XCTAssertEqual(mode(shape), .shapeStatus)
        for panel in [PlaybackInlinePanel.settings, .playbackSpeed, .savedReviews] {
            XCTAssertFalse(panel.isAnnotationPanel)
            XCTAssertEqual(mode(shape, hasWorkflow: panel.isAnnotationPanel), .shapeStatus)
        }
        let match = ReplayStore()
        match.prepareForLocalExperience()
        XCTAssertNotEqual(match.selectedScenario.kind, .shapeLab)
        XCTAssertEqual(mode(match), .matchPlayback)
        XCTAssertEqual(mode(match, hasWorkflow: true), .matchPlayback)
        match.beginDrawing(.pass)
        XCTAssertEqual(mode(match, hasWorkflow: true), .annotationDrawing)
        match.cancelDrawing()
        XCTAssertEqual(mode(match), .matchPlayback)
    }

    func testAuthoredSelectionExpiryCannotUnmountAnOwningShapeTimeline() throws {
        let store = makeStore(stage: .problem)
        let preset = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        store.seek(to: preset.revealTime, broadcast: false)
        var selectedID: UUID? = preset.id
        XCTAssertEqual(mode(store, hasWorkflow: selectedID != nil), .shapeAnnotations)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: preset.revealTime - 0.5))

        // The common playhead observer clears an authored overlay as soon as
        // it is no longer rendered. The transaction still owns this rail.
        XCTAssertFalse(preset.isVisible(at: store.playhead))
        selectedID = nil
        XCTAssertNil(selectedID)
        XCTAssertEqual(mode(store, hasWorkflow: store.hasActiveTimelineScrub), .shapeAnnotations)
        XCTAssertFalse(store.canChangePlaybackView)

        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, preset.revealTime)
        XCTAssertTrue(store.canChangePlaybackView)
        XCTAssertEqual(mode(store, hasWorkflow: selectedID != nil), .shapeStatus)
    }

    func testLiveDeckUsesTheTestedRoutingPolicyAndExistingWorkflowState() throws {
        let source = try immersiveSource()
        XCTAssertTrue(source.contains("switch PlaybackControlDeckPresentation.mode("))
        XCTAssertTrue(source.contains("hasAnnotationWorkflow: shapeAnnotationWorkflowIsPresented"))
        let start = try XCTUnwrap(source.range(of: "private var shapeAnnotationWorkflowIsPresented: Bool")?.upperBound)
        let end = try XCTUnwrap(source.range(of: "private var matchPlaybackDeck: some View", range: start..<source.endIndex)?.lowerBound)
        let workflow = source[start..<end]
        for state in ["selectedAnnotation != nil", "store.hasActiveTimelineScrub", "store.hasActiveCoachMarkGeometryPreview", "isClearAnnotationsPending", "showsEventStrip", "showsAnnotationTools", "inlinePanel?.isAnnotationPanel == true"] {
            XCTAssertTrue(workflow.contains(state), state)
        }
    }

    func testShapeEntryAndWorkspaceReuseTheExistingAnnotationWorkflowsWithoutMatchTransport() throws {
        let source = try immersiveSource()
        let status = try slice(source, after: "private var shapeFocusStatusDeck: some View", before: "private func formatTime(")
        XCTAssertTrue(status.contains("annotationToolsButton"), "A coach needs a normal Draw entry, not only a restored selection")
        let entry = try slice(source, after: "private var annotationToolsButton: some View", before: "private var controlDeckPreset:")
        XCTAssertTrue(entry.contains("showsAnnotationTools = opensTools"))
        XCTAssertTrue(entry.contains("showsPlaybackAnnotations = true"))

        let workspace = try slice(source, after: "private var shapeAnnotationDeck: some View", before: "private var shapeFocusStatusDeck:")
        for sharedView in ["timelineScrubber", "selectedAnnotationInspector(selectedAnnotation)", "inlinePanelShelf(inlinePanel)", "annotationEventStrip", "clearAnnotationsConfirmationStrip", "coachAnnotationStrip", "annotationEditButton(compact: true)"] {
            XCTAssertTrue(workspace.contains(sharedView), sharedView)
        }
        for matchOnlyControl in ["matchPlaybackDeck", "handlePrimaryPlaybackAction", "compactSpeedControlButton", "compactPlayerControlButton", "playbackToolsButton"] {
            XCTAssertFalse(workspace.contains(matchOnlyControl), matchOnlyControl)
        }
        XCTAssertTrue(workspace.contains("Close Shape annotation tools"))
    }

    func testSharedCloseBackAndLifecycleKeepHeldGesturesAndSelectionCleanupOwned() throws {
        let source = try immersiveSource()
        let sections = [
            ("private func inlinePanelHeader(", "private var inlineChoiceDivider:"),
            ("private var annotationEventStrip:", "private func eventPageButton("),
            ("private func selectedAnnotationInspector(", "private func annotationGeometryButton("),
            ("private var shapeAnnotationDeck:", "private var shapeFocusStatusDeck:")
        ]
        for (start, end) in sections {
            let navigation = try slice(source, after: start, before: end)
            XCTAssertTrue(navigation.contains("guard store.canChangePlaybackView else { return }"), start)
            XCTAssertTrue(navigation.contains(".disabled(!store.canChangePlaybackView)"), start)
            XCTAssertTrue(navigation.contains("Finish the current gesture first"), start)
        }
        let host = try slice(source, after: "private func annotationWorkflowHost<Content: View>", before: "private var playbackToolsButton:")
        for observer in ["store.selectedScenarioID", "store.reviewIndexVersion", "selectedAnnotationID", "store.playhead"] {
            XCTAssertTrue(host.contains(".onChange(of: \(observer))"), observer)
        }
        XCTAssertTrue(host.contains("cancelInterruptedTimelineScrub()"))
        XCTAssertTrue(host.contains("rebuildReviewIndex()"))
        XCTAssertTrue(host.contains("self.selectedAnnotationID = nil"))

        let drawing = try slice(source, after: "private var annotationDrawingShelf:", before: "private var coachAnnotationStrip:")
        XCTAssertTrue(drawing.contains("store.cancelDrawing()"), "An explicit draft Cancel stays available")
        let deckStart = try XCTUnwrap(source.range(of: "private struct ImmersiveControlDeck:")?.lowerBound)
        let deckEnd = try XCTUnwrap(source.range(of: "private var matchPlaybackDeck:", range: deckStart..<source.endIndex)?.lowerBound)
        let deck = source[deckStart..<deckEnd]
        XCTAssertTrue(deck.contains("annotationWorkflowHost {"))
        XCTAssertTrue(deck.contains("cancelInterruptedTimelineScrub()"))
    }

    private func immersiveSource() throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"
        ), encoding: .utf8)
    }

    private func slice(_ source: String, after startMarker: String, before endMarker: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.upperBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }

    private func mode(_ store: ReplayStore, hasWorkflow: Bool = false) -> PlaybackControlDeckPresentation.Mode {
        PlaybackControlDeckPresentation.mode(
            isPhysicalPlacement: store.triangleLockMode == .place,
            isShapeFocus: store.selectedScenario.kind == .shapeLab,
            isDrawing: store.isDrawing,
            hasAnnotationWorkflow: hasWorkflow
        )
    }

    private func makeStore(stage: ShapeFocusStage) -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(stage, broadcast: false)
        return store
    }

    private func drawPlayerRun(in store: ReplayStore) throws -> CoachMark {
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(store.presentedPlayerPose(for: player, at: store.playhead).position))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 28, z: 34)))
        XCTAssertEqual(mark.startTrackAnchor?.playerID, player.id)
        XCTAssertFalse(store.isDrawing)
        return mark
    }
}
