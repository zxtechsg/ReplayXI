import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackClearConfirmationOwnershipTests: XCTestCase {
    func testClearConfirmationUsesTheSameGestureGateAsItsEntryButton() throws {
        let source = try immersiveSource()
        let entry = try slice(source,
            after: "private var annotationEditShelf: some View",
            before: "private func annotationActionsShelf")
        let confirmation = try clearConfirmation(source)
        let gate = ".disabled(clearableCoachAnnotationCount == 0 || !store.canChangePlaybackView)"
        XCTAssertTrue(entry.contains(gate), "The entry already rejects an owned gesture")
        XCTAssertTrue(confirmation.contains(gate), "A scrub can start after confirmation opens")
    }

    func testClearCallbackChecksAdmissionBeforeClaimingSuccessOrClosingConfirmation() throws {
        let confirmation = try clearConfirmation(immersiveSource())
        let callback = try slice(confirmation,
            after: "Button(role: .destructive) {", before: "} label: {")
        let admission = callback.range(of: "guard store.canChangePlaybackView")?.lowerBound
        XCTAssertNotNil(admission, "A queued Clear callback must reject a gesture before any UI side effects")
        XCTAssertTrue(callback.contains("store.localRole == .coach"))
        XCTAssertTrue(callback.contains("clearableCoachAnnotationCount > 0"))
        for sideEffect in [
            "store.clearMarks()", "selectedAnnotationID = nil",
            "isClearAnnotationsPending = false", "annotationConfirmation = \"MARKS CLEARED\"",
            "inlinePanel = .annotationEdit"
        ] {
            let effect = try XCTUnwrap(callback.range(of: sideEffect)?.lowerBound)
            if let admission { XCTAssertLessThan(admission, effect) }
        }
    }

    func testCancelOnlyClosesConfirmationAndLeavesTheOwningRailUsable() throws {
        let source = try immersiveSource()
        let confirmation = try clearConfirmation(source)
        let cancel = try slice(confirmation,
            after: "Button(\"Cancel\") {", before: "Button(role: .destructive)")
        XCTAssertTrue(cancel.contains("isClearAnnotationsPending = false"))
        XCTAssertFalse(cancel.contains("store."), "Closing this confirmation must not cancel or seek the timeline")
        XCTAssertFalse(cancel.contains(".disabled("), "Cancel remains usable while the other hand owns a scrub")

        let railGate = try slice(source,
            after: "private var timelineControlsAreDisabled: Bool",
            before: "private var rateControlsAreDisabled:")
        XCTAssertFalse(railGate.contains("isClearAnnotationsPending"))
        XCTAssertTrue(railGate.contains("store.hasActiveTimelineScrub"))
        XCTAssertTrue(railGate.contains("timelineScrubController.storeScrubID != store.activeTimelineScrubID"),
                      "A foreign rail may block input, but this rail must retain its own drag")
        XCTAssertFalse(railGate.contains("canChangePlaybackView"))
    }

    func testStoreRejectsClearDuringHeldScrubWithoutChangingMarksHistoryOrCheckpoint() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        _ = try addCoachMark(to: store)
        let committedMarks = store.marks
        let undoTitle = store.annotationUndoTitle
        store.seek(to: 5, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 12))
        let committedSnapshot = store.makeSnapshot()
        XCTAssertFalse(store.canChangePlaybackView)

        store.clearMarks()

        XCTAssertEqual(store.marks, committedMarks)
        XCTAssertEqual(store.annotationUndoTitle, undoTitle)
        XCTAssertEqual(store.playhead, 12)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.makeSnapshot(), committedSnapshot)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the timeline scrub first")
        XCTAssertTrue(store.previewTimelineScrub(to: 14), "The owning rail can still continue")
        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(store.marks, committedMarks)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.canChangePlaybackView)
    }

    func testNormalClearKeepsMatchOverlaysAndUndoRestoresEveryCoachMark() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let fixtureMarks = store.marks
        _ = try addCoachMark(to: store)
        let committedMarks = store.marks
        XCTAssertTrue(store.canChangePlaybackView)

        store.clearMarks()

        XCTAssertEqual(store.marks, fixtureMarks)
        XCTAssertEqual(store.statusMessage, "New annotations cleared")
        XCTAssertEqual(store.annotationUndoTitle, "Undo erase", "History labels a single removed mark as erase")
        XCTAssertTrue(store.canUndoAnnotationEdit)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, committedMarks)
    }

    private func addCoachMark(to store: ReplayStore) throws -> CoachMark {
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -4, z: 2)))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 4, z: 10)))
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
    }

    private func clearConfirmation(_ source: String) throws -> String {
        try slice(source,
            after: "private var clearAnnotationsConfirmationStrip: some View",
            before: "private func applyAnnotationHistory")
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
