import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingDraftSessionTests: XCTestCase {
    private func fixture() throws -> (ReplayStore, CoachMark, AnnotationTimingDraftSession) {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 5, z: 5)))
        XCTAssertTrue(store.setCoachMarkDuration(id: created.id, duration: 8))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 6)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 4)
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration, store: store))
        return (store, mark, session)
    }

    func testRemountKeepsBothDraftsAndRejectsNewOwner() throws {
        let (store, mark, session) = try fixture()
        session.window.startText = "1"
        XCTAssertTrue(session.position.select(6))
        session.position.text = "7"
        XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration))
        XCTAssertEqual(session.window.startText, "1")
        XCTAssertEqual(session.position.text, "7")
        let other = CoachMark(kind: .run, start: mark.start, end: mark.end, label: "Other")
        XCTAssertFalse(session.begin(mark: other, scenarioID: store.selectedScenarioID,
                                     duration: store.selectedScenario.duration))
        XCTAssertEqual(session.markID, mark.id)
    }

    func testApplyBothDraftsIsOneUndoAndDoesNotMovePlayhead() throws {
        let (store, mark, session) = try fixture()
        let baseline = store.marks
        session.window.startText = "1"; session.window.endText = "9"
        XCTAssertTrue(session.position.select(6)); session.position.text = "7"
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertTrue(session.canApply(in: store))
        XCTAssertTrue(session.apply(in: store))
        XCTAssertFalse(session.hasUnsavedChanges)
        let edited = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(edited.revealTime, 1)
        XCTAssertEqual(edited.hideTime, 9)
        XCTAssertEqual(edited.keyframes?.map(\.time), [2, 7])
        XCTAssertEqual(store.playhead, 4)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
    }

    func testInvalidPositionDoesNotPartiallyApplyValidWindow() throws {
        let (store, _, session) = try fixture()
        let baseline = store.marks
        session.window.startText = "1"
        XCTAssertTrue(session.position.select(6)); session.position.text = "2"
        XCTAssertFalse(session.canApply(in: store), "Destination collides with another position")
        XCTAssertFalse(session.apply(in: store))
        XCTAssertEqual(store.marks, baseline)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testDiscardChangesOnlyDraftsNotSavedAnnotations() throws {
        let (store, _, session) = try fixture()
        let baseline = store.marks
        session.window.startText = "invalid"
        XCTAssertTrue(session.position.select(6)); session.position.text = "7"
        session.discard(in: store)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(store.marks, baseline)
        XCTAssertEqual(store.playhead, 4)
    }

    func testApplyingWindowPreservesPendingPositionTimeAndOwnership() throws {
        let (store, mark, session) = try fixture()
        session.window.startText = "1"
        XCTAssertTrue(session.position.select(6)); session.position.text = "7"

        XCTAssertTrue(store.setCoachMarkWindow(id: mark.id, start: 1, end: mark.hideTime))
        session.resetWindow(mark: try XCTUnwrap(store.marks.first { $0.id == mark.id }),
                            duration: store.selectedScenario.duration)
        XCTAssertFalse(session.windowIsDirty)
        XCTAssertEqual(session.position.text, "7")
        XCTAssertTrue(session.position.isDirty)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)

        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 7))
        session.position.acceptCommittedTime(7)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
    }

    func testMovingPositionPreservesPendingWindowAndOwnership() throws {
        let (store, mark, session) = try fixture()
        session.window.startText = "1:"
        XCTAssertTrue(session.position.select(6)); session.position.text = "7"

        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 6, to: 7))
        session.position.acceptCommittedTime(7)
        XCTAssertFalse(session.position.isDirty)
        XCTAssertEqual(session.window.startText, "1:")
        XCTAssertTrue(session.windowIsDirty)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)

        session.resetWindow(mark: try XCTUnwrap(store.marks.first { $0.id == mark.id }),
                            duration: store.selectedScenario.duration)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
    }

    func testSessionCannotApplyWhileAnotherAnnotationOwnsPendingChanges() throws {
        let (store, mark, session) = try fixture()
        store.beginDrawing(.run)
        _ = store.registerPitchTap(.init(x: 2, z: 2))
        let other = try XCTUnwrap(store.registerPitchTap(.init(x: 6, z: 6)))
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: other.id, isPending: true))
        let baseline = store.marks

        session.window.startText = "1"
        XCTAssertEqual(store.pendingAnnotationTimingEditID, other.id)
        XCTAssertFalse(session.canApply(in: store))
        XCTAssertFalse(session.apply(in: store))
        XCTAssertEqual(store.marks, baseline)
        session.releaseOwnership()
        XCTAssertEqual(store.pendingAnnotationTimingEditID, other.id)
        XCTAssertNotEqual(mark.id, other.id)
    }

    func testDifferentScenarioNeverReceivesPendingDraft() throws {
        let (store, _, session) = try fixture()
        session.window.startText = "1"
        session.releaseOwnership() // Simulate a system disappearance, not a permitted navigation.
        let other = try XCTUnwrap(store.scenarios.first { $0.id != store.selectedScenarioID })
        store.selectScenario(id: other.id)
        let current = store.marks
        XCTAssertFalse(session.canApply(in: store))
        XCTAssertFalse(session.apply(in: store))
        session.discard(in: store)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(store.marks, current)
    }

    func testFixtureAnnotationRemainsImmutable() throws {
        let store = ReplayStore()
        let mark = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: mark, scenarioID: store.selectedScenarioID,
                                    duration: store.selectedScenario.duration))
        session.window.startText = AnnotationTimestamp.editable(mark.revealTime + 1)
        XCTAssertFalse(session.canApply(in: store))
        XCTAssertFalse(session.apply(in: store))
        XCTAssertTrue(store.marks.contains(mark))
    }

    func testTypedInputImmediatelyBlocksNavigationWithoutRendering() throws {
        let (store, mark, session) = try fixture()
        let scenarioID = store.selectedScenarioID
        let other = try XCTUnwrap(store.scenarios.first { $0.id != scenarioID })
        session.window.startText = "1:"
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
        store.selectScenario(id: other.id)
        XCTAssertEqual(store.selectedScenarioID, scenarioID)
        session.discard(in: store)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertTrue(session.position.select(6))
        session.position.text = "7"
        XCTAssertEqual(store.pendingAnnotationTimingEditID, mark.id)
        XCTAssertFalse(store.removeCoachMark(id: mark.id))
        session.releaseOwnership()
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        session.position.text = "8"
        XCTAssertNil(store.pendingAnnotationTimingEditID, "Detached editor bindings must not revive a dead UI lock")
    }

    func testGateProtectsCloseBackSelectionAndDrawerRoutesWithoutLosingIntent() {
        let id = UUID()
        let source = route(id)
        var destinations: [AnnotationTimingDeckRoute] = []
        var close = source; close.panel = nil; destinations.append(close)
        var back = source; back.selection = nil; back.panel = nil; back.showsEvents = true; destinations.append(back)
        var other = source; other.selection = UUID(); destinations.append(other)
        var tools = source; tools.panel = nil; tools.showsTools = true; destinations.append(tools)
        var hide = source; hide.showsAnnotations = false; destinations.append(hide)
        for destination in destinations {
            var gate = AnnotationTimingNavigationGate()
            gate.observeDraft(isDirty: true, route: source)
            XCTAssertEqual(gate.protect(destination), source)
            XCTAssertEqual(gate.request, .route(destination))
            _ = gate.protect(back)
            XCTAssertEqual(gate.request, .route(destination), "Rollback observers cannot replace the first destination")
            XCTAssertEqual(gate.consume(), .route(destination))
            XCTAssertNil(gate.protectedRoute)
        }
    }

    func testKeepEditingRetainsProtectionAndExitNeedsExplicitResolution() {
        let source = route(UUID())
        var gate = AnnotationTimingNavigationGate()
        gate.observeDraft(isDirty: true, route: source)
        gate.ask(.exit)
        gate.keepEditing()
        XCTAssertNil(gate.request)
        XCTAssertEqual(gate.protectedRoute, source)
        gate.ask(.retryExternalAction)
        XCTAssertEqual(gate.consume(), .retryExternalAction)
        gate.observeDraft(isDirty: false, route: source)
        var close = source; close.panel = nil
        XCTAssertNil(gate.protect(close))
    }

    func testNativeEditorRemountRetainsTypedText() throws {
        let (store, mark, session) = try fixture()
        func editor() -> AnyView {
            AnyView(AnnotationTimingEditor(markID: mark.id, color: ReplayTheme.cyan, draftSession: session)
                .environment(store).frame(width: 1100))
        }
        let host = UIHostingController(rootView: editor())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 700))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        func settle() {
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        settle()
        session.window.startText = "1:"
        XCTAssertTrue(session.position.select(6)); session.position.text = "7"
        host.rootView = AnyView(Text("Resolve pending timing")); settle()
        host.rootView = editor(); settle()
        XCTAssertEqual(session.window.startText, "1:")
        XCTAssertEqual(session.position.text, "7")
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testNativeInlineResolutionFitsLargestTextWithoutModalPresentation() throws {
        let view = AnnotationTimingDraftResolutionView(canApply: false, needsRetry: true,
            keepEditing: {}, discard: {}, apply: {})
            .buttonStyle(.bordered).controlSize(.extraLarge).dynamicTypeSize(.accessibility5)
            .padding(24).frame(width: 1000).background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: 1000, height: 1400))
        XCTAssertLessThanOrEqual(size.width, 1000)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: ceil(size.height)))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "unsaved-timing-inline-resolution-largest-text"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func route(_ id: UUID) -> AnnotationTimingDeckRoute {
        .init(selection: id, panel: .annotationDuration(id), showsTools: false, showsPlayers: false,
              showsEvents: false, showsDecisions: false, showsDrawing: false, showsClear: false,
              showsAnnotations: true)
    }
}
