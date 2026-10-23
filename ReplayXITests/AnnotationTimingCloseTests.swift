import XCTest
@testable import ReplayXI

/// Route/session behavior plus production wiring. Native captures separately
/// check the fixed header; these tests do not claim headset button activation.
@MainActor
final class AnnotationTimingCloseTests: XCTestCase {
    func testCleanCloseReturnsToSameInspectorWithoutSeekingOrWriting() throws {
        let (store, mark, session) = try fixture()
        let before = store.makeSavedReviewState()
        let source = route(mark.id)
        var destination = source; destination.panel = nil
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        XCTAssertNil(gate.protect(destination))
        XCTAssertNil(gate.request)
        XCTAssertEqual(destination.selection, mark.id)
        XCTAssertNil(destination.panel)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testDirtyCloseKeepEditingPreservesBothDraftsAndSavedReplay() throws {
        let (store, mark, session) = try fixture(dirty: true)
        let before = store.makeSavedReviewState()
        let source = route(mark.id)
        var destination = source; destination.panel = nil
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        XCTAssertEqual(gate.protect(destination), source)
        XCTAssertEqual(gate.request, .route(destination))
        XCTAssertEqual(gate.protectedRoute?.selection, mark.id)
        gate.keepEditing()
        XCTAssertNil(gate.request)
        XCTAssertEqual(gate.protectedRoute, source)
        XCTAssertEqual(session.window.startText, "1")
        XCTAssertEqual(session.window.endText, "9")
        XCTAssertEqual(session.position.selectedTime, 6)
        XCTAssertEqual(session.position.text, "7")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state, before, "Close never autosaves typed drafts")
    }

    func testDiscardCloseChangesOnlyDraftsAndReturnsToSameInspector() throws {
        let (store, mark, session) = try fixture(dirty: true)
        let before = store.makeSavedReviewState()
        let source = route(mark.id)
        var destination = source; destination.panel = nil
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        XCTAssertEqual(gate.protect(destination), source)
        session.discard(in: store)
        session.releaseOwnership()
        XCTAssertEqual(gate.consume(), .route(destination))
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertEqual(destination.selection, mark.id)
        XCTAssertNil(destination.panel)
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testApplyCloseCommitsBothDraftsOnceWithoutMovingTimeOrSelection() throws {
        let (store, mark, session) = try fixture(dirty: true)
        let before = store.marks
        let source = route(mark.id)
        var destination = source; destination.panel = nil
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        XCTAssertEqual(gate.protect(destination), source)
        XCTAssertTrue(session.apply(in: store))
        session.releaseOwnership()
        XCTAssertEqual(gate.consume(), .route(destination))
        XCTAssertEqual(destination.selection, mark.id)
        XCTAssertNil(destination.panel)
        let edited = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(edited.revealTime, 1)
        XCTAssertEqual(edited.hideTime, 9)
        XCTAssertEqual(edited.keyframes?.map(\.time), [2, 7])
        XCTAssertEqual(store.playhead, 4)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        XCTAssertEqual(store.playhead, 4)
    }

    func testInvalidDraftCannotPartiallyApplyOrConsumeCloseRequest() throws {
        let (store, mark, session) = try fixture(dirty: true)
        session.window.startText = "1:"
        let before = store.makeSavedReviewState()
        let source = route(mark.id)
        var destination = source; destination.panel = nil
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        XCTAssertEqual(gate.protect(destination), source)
        XCTAssertFalse(session.canApply(in: store))
        XCTAssertFalse(session.apply(in: store))
        XCTAssertEqual(gate.request, .route(destination))
        gate.keepEditing()
        XCTAssertEqual(gate.protectedRoute, source)
        XCTAssertEqual(session.window.startText, "1:")
        XCTAssertEqual(session.position.text, "7")
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testLiveEditorCloseKeepsTheGestureGateWithoutAnOnHeadsetTimingEditor() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let editor = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/SpatialAnnotationEditor.swift"), encoding: .utf8)
        XCTAssertTrue(editor.contains("action(\"Close\", \"xmark\", onClose)"))
        XCTAssertTrue(editor.contains(".disabled(!store.canChangePlaybackView)"))
        let deck = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertFalse(deck.contains("AnnotationTimingEditor("))
        let start = try XCTUnwrap(deck.range(of: "private func selectedAnnotationInspector(")?.lowerBound)
        let end = try XCTUnwrap(deck.range(of: "private func nudgeAnnotation(")?.lowerBound)
        let handler = deck[start..<end]
        XCTAssertTrue(handler.contains("guard store.canChangePlaybackView else { return }"))
        XCTAssertFalse(handler.contains("store.seek"))
        XCTAssertFalse(handler.contains("freezeCoachMarkKeyframes"))
    }

    private func fixture(dirty: Bool = false) throws -> (ReplayStore, CoachMark, AnnotationTimingDraftSession) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        XCTAssertTrue(store.setCoachMarkDuration(id: created.id, duration: 8))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 6)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 4)
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration, store: store))
        XCTAssertTrue(session.position.select(6))
        if dirty {
            session.window.startText = "1"
            session.window.endText = "9"
            session.position.text = "7"
        }
        return (store, mark, session)
    }

    private func route(_ id: UUID) -> AnnotationTimingDeckRoute {
        .init(selection: id, panel: .annotationDuration(id), showsTools: false, showsPlayers: false,
              showsEvents: false, showsDecisions: false, showsDrawing: false, showsClear: false,
              showsAnnotations: true)
    }
}
