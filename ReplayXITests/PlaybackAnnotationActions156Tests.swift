import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationActions156Tests: XCTestCase {
    func testActionsAreIDBoundAndRetractWithoutChangingSelection() {
        let id = UUID(), other = UUID()
        let panel = PlaybackInlinePanel.annotationActions(id)
        XCTAssertTrue(panel.isAnnotationPanel)
        XCTAssertTrue(panel.isValid(for: id))
        XCTAssertFalse(panel.isValid(for: other))
        XCTAssertFalse(panel.isValid(for: nil))
        XCTAssertEqual(panel.annotationID, id)
        let source = route(id, panel: nil)
        let opened = PlaybackAnnotationActionsRoute.destination(id: id, from: source)
        XCTAssertEqual(opened.selection, id)
        XCTAssertEqual(opened.panel, panel)
        let closed = PlaybackAnnotationActionsRoute.destination(id: id, from: opened)
        XCTAssertEqual(closed.selection, id)
        XCTAssertNil(closed.panel)
        XCTAssertTrue(closed.showsAnnotations)
        XCTAssertEqual(PlaybackAnnotationActionsRoute.accessibilityHint(isSpatial: false, isAuthored: false),
                       "Opens Delete everywhere for this label")
        XCTAssertFalse(PlaybackAnnotationActionsRoute.accessibilityHint(isSpatial: true, isAuthored: true).contains("Erase"))
        XCTAssertTrue(PlaybackAnnotationActionsRoute.accessibilityHint(isSpatial: true, isAuthored: false).contains("Delete everywhere"))
    }

    func testSelectionObserverRetainsOnlyAlreadyMatchedAnnotationPanels() {
        let id = UUID(), other = UUID()
        let panels: [PlaybackInlinePanel] = [.annotationActions(id), .annotationGeometry(id),
            .annotationDuration(id), .annotationLabel(id), .annotationTracking(id)]
        for panel in panels {
            XCTAssertEqual(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(panel, selectedID: id), panel)
            XCTAssertNil(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(panel, selectedID: other))
            XCTAssertNil(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(panel, selectedID: nil))
        }
        let globalPanels: [PlaybackInlinePanel] = [.settings, .savedReviews, .playbackSpeed, .annotationEdit]
        for panel in globalPanels {
            XCTAssertNil(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(panel, selectedID: id))
        }
        XCTAssertEqual(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(.annotationEdit, selectedID: nil), .annotationEdit)
        XCTAssertNil(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(.settings, selectedID: nil))
        XCTAssertNil(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(nil, selectedID: id))
    }

    func testCopySelectionSurvivesBothObserverOrdersButOrdinaryDrawingStillClosesSelection() throws {
        for countFirst in [false, true] {
            let (store, source) = try fixture()
            store.seek(to: 0, broadcast: false)
            XCTAssertFalse(source.isVisible(at: store.playhead), "Copy has no source visibility gate")
            let oldCount = store.marks.count
            let copied = try XCTUnwrap(PlaybackAnnotationActionsRoute.copyPose(id: source.id,
                selectedID: source.id, panel: .annotationActions(source.id), timingIsDirty: false, in: store))
            var selectedID: UUID? = copied.id
            var panel: PlaybackInlinePanel? = .annotationGeometry(copied.id)
            @MainActor func observeCount() {
                if !PlaybackAnnotationActionsRoute.keepsSelectedInsertion(
                    insertedID: copied.id, selectedID: selectedID, panel: panel) { selectedID = nil }
            }
            @MainActor func observeSelection() {
                panel = PlaybackAnnotationActionsRoute.panelAfterSelectionChange(panel, selectedID: selectedID)
            }
            if countFirst { observeCount(); observeSelection() } else { observeSelection(); observeCount() }
            XCTAssertEqual(selectedID, copied.id)
            XCTAssertEqual(panel, .annotationGeometry(copied.id))
            XCTAssertEqual(store.marks.count, oldCount + 1)
            XCTAssertEqual(store.marks.first { $0.id == source.id }, source)
            XCTAssertFalse(PlaybackAnnotationActionsRoute.keepsSelectedInsertion(
                insertedID: copied.id, selectedID: source.id, panel: .annotationGeometry(source.id)))
            XCTAssertFalse(PlaybackAnnotationActionsRoute.keepsSelectedInsertion(
                insertedID: copied.id, selectedID: copied.id, panel: .settings))
            XCTAssertFalse(PlaybackAnnotationActionsRoute.keepsSelectedInsertion(
                insertedID: copied.id, selectedID: nil, panel: nil))
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks.count, oldCount)
            XCTAssertFalse(store.marks.contains { $0.id == copied.id })
        }
    }

    func testStaleOrDirtyActionsCannotCopyAnotherSelectionOrMutateTransport() throws {
        let (store, source) = try fixture()
        store.setPlaying(true, broadcast: false)
        let before = store.makeSnapshot(), saved = store.makeSavedReviewState()
        let undo = store.annotationUndoTitle
        let other = UUID()
        let cases: [(UUID?, PlaybackInlinePanel?, Bool)] = [
            (other, .annotationActions(source.id), false),
            (source.id, .annotationActions(other), false),
            (source.id, .annotationGeometry(source.id), false),
            (source.id, nil, false), (nil, nil, false),
            (source.id, .annotationActions(source.id), true)
        ]
        for (selection, panel, dirty) in cases {
            var failures: [String] = []
            XCTAssertNil(PlaybackAnnotationActionsRoute.copyPose(id: source.id, selectedID: selection,
                panel: panel, timingIsDirty: dirty, in: store, onFailure: { failures.append($0) }))
            XCTAssertTrue(failures.isEmpty, "Rejected UI routes must not surface an unrelated Store status")
            XCTAssertEqual(store.makeSnapshot(), before)
            XCTAssertEqual(store.makeSavedReviewState(), saved)
            XCTAssertEqual(store.annotationUndoTitle, undo)
        }
        XCTAssertTrue(store.removeCoachMark(id: source.id))
        let afterErase = store.marks
        var failure: String?
        XCTAssertNil(PlaybackAnnotationActionsRoute.copyPose(id: source.id, selectedID: source.id,
            panel: .annotationActions(source.id), timingIsDirty: false, in: store, onFailure: { failure = $0 }))
        XCTAssertEqual(failure, "Choose a spatial annotation to copy")
        XCTAssertEqual(store.marks, afterErase)
    }

    func testDirtyTimingActionsWaitForApplyOrDiscardAndKeepEditingDoesNotCopy() throws {
        for applies in [false, true] {
            let (store, mark) = try fixture()
            let session = AnnotationTimingDraftSession()
            XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                duration: store.selectedScenario.duration, store: store))
            session.window.startText = "1"
            let source = route(mark.id, panel: .annotationDuration(mark.id))
            let destination = PlaybackAnnotationActionsRoute.destination(id: mark.id, from: source)
            let count = store.marks.count, baseline = store.makeSavedReviewState()
            var gate = AnnotationTimingNavigationGate()
            gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
            XCTAssertEqual(gate.protect(destination), source)
            XCTAssertNil(PlaybackAnnotationActionsRoute.copyPose(id: mark.id, selectedID: mark.id,
                panel: destination.panel, timingIsDirty: session.hasUnsavedChanges, in: store))
            XCTAssertEqual(store.makeSavedReviewState(), baseline)
            gate.keepEditing()
            XCTAssertTrue(session.hasUnsavedChanges)
            XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
            XCTAssertEqual(store.marks.count, count)
            XCTAssertEqual(gate.protect(destination), source)
            if applies { XCTAssertTrue(session.apply(in: store)) } else { session.discard(in: store) }
            session.releaseOwnership()
            XCTAssertEqual(gate.consume(), .route(destination))
            XCTAssertEqual(store.marks.count, count, "Resolving timing only opens Actions; it must not copy yet")
            let copied = try XCTUnwrap(PlaybackAnnotationActionsRoute.copyPose(id: mark.id,
                selectedID: destination.selection, panel: destination.panel,
                timingIsDirty: session.hasUnsavedChanges, in: store))
            XCTAssertEqual(store.marks.count, count + 1)
            XCTAssertNotEqual(copied.id, mark.id)
            XCTAssertFalse(session.hasUnsavedChanges)
            XCTAssertEqual(store.marks.first { $0.id == mark.id }?.revealTime, applies ? 1 : 2)
        }
    }

    func testAdmittedLegacyShortPoseReportsFreshFailureWithoutChangingReplay() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let short = CoachMark(kind: .arc, start: .zero, end: .init(x: 0.1, z: 0),
                              curve: .init(bend: 1, lift: 0), label: "Old short arc")
        XCTAssertTrue(store.appendRemoteCoachMark(short))
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.canCopyCoachMarkPose(id: short.id), "The final geometry check owns this failure")
        let before = store.makeSnapshot(), undo = store.annotationUndoTitle
        var feedback: String?
        XCTAssertNil(PlaybackAnnotationActionsRoute.copyPose(id: short.id, selectedID: short.id,
            panel: .annotationActions(short.id), timingIsDirty: false, in: store, onFailure: { feedback = $0 }))
        XCTAssertEqual(feedback, "Choose a pose large enough to copy")
        XCTAssertEqual(store.makeSnapshot(), before)
        XCTAssertEqual(store.annotationUndoTitle, undo)
    }

    func testAuthoredPoseRouteCopiesWithoutUnlockingOrEditingSource() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let source = try XCTUnwrap(store.selectedScenario.coachMarks.first { $0.kind.requiresTwoPitchPoints })
        store.seek(to: source.revealTime, broadcast: false)
        let before = store.marks
        XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))
        let copied = try XCTUnwrap(PlaybackAnnotationActionsRoute.copyPose(id: source.id,
            selectedID: source.id, panel: .annotationActions(source.id), timingIsDirty: false, in: store))
        XCTAssertEqual(Array(store.marks.dropLast()), before)
        XCTAssertFalse(store.selectedScenario.coachMarks.contains { $0.id == copied.id })
        XCTAssertFalse(store.removeCoachMark(id: source.id))
        XCTAssertEqual(store.marks.first { $0.id == source.id }, source)
        XCTAssertEqual(PlaybackAnnotationActionsRoute.panelAfterSelectionChange(
            .annotationGeometry(copied.id), selectedID: copied.id), .annotationGeometry(copied.id))
    }

    func testProductionWiringKeepsCopyOffMainBarAndProtectsBeforeOpeningActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("PlaybackAnnotationActionsRoute.keepsSelectedInsertion("))
        XCTAssertTrue(source.contains("PlaybackAnnotationActionsRoute.panelAfterSelectionChange("))
        XCTAssertTrue(source.contains("onActions: { toggleAnnotationActions(id: mark.id) }"))
        XCTAssertTrue(source.contains("inlinePanel = .annotationGeometry(copied.id)"))
        let start = try XCTUnwrap(source.range(of: "private func toggleAnnotationActions(id:")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func copyAnnotationPose(id:")?.lowerBound)
        let toggle = source[start..<end]
        XCTAssertTrue(toggle.contains("timingNavigation.protect(destination)"))
        XCTAssertFalse(toggle.contains("copyCoachMarkPose"))
        let barStart = try XCTUnwrap(source.range(of: "private var matchPlaybackDeck:")?.lowerBound)
        let barEnd = try XCTUnwrap(source.range(of: "if timingNavigation.request != nil", range: barStart..<source.endIndex)?.lowerBound)
        XCTAssertFalse(source[barStart..<barEnd].contains("annotationActions"))
        XCTAssertFalse(source[barStart..<barEnd].contains("copyAnnotationPose"))
        let tickStart = try XCTUnwrap(source.range(of: ".onChange(of: store.playhead) { _, playhead in")?.lowerBound)
        let tickEnd = try XCTUnwrap(source.range(of: ".task {", range: tickStart..<source.endIndex)?.lowerBound)
        XCTAssertFalse(source[tickStart..<tickEnd].contains("annotationActionsFeedback = nil"),
                       "A failed copy must not lose its feedback on the next playing frame")
    }

    private func fixture() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 2, broadcast: false)
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        store.cancelDrawing()
        return (store, try XCTUnwrap(store.marks.first { $0.id == created.id }))
    }

    private func route(_ id: UUID, panel: PlaybackInlinePanel?) -> AnnotationTimingDeckRoute {
        .init(selection: id, panel: panel, showsTools: false, showsPlayers: false,
              showsEvents: false, showsDecisions: false, showsDrawing: false, showsClear: false,
              showsAnnotations: true)
    }
}
