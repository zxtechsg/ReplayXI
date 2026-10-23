import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackDiscreteTransportOwnershipTests: XCTestCase {
    func testPreviousAndNextEventButtonsUseTheDiscreteNavigationGate() throws {
        let source = try immersiveSource()
        let row = try slice(source, after: "private var matchPlaybackDeck: some View", before: "if isClearAnnotationsPending")
        XCTAssertTrue(row.contains("playbackEventStepButton(.previous)"))
        XCTAssertTrue(row.contains("playbackEventStepButton(.next)"))
        let control = try slice(source, after: "private func playbackEventStepButton(", before: "private var previousCue:")
        XCTAssertTrue(control.contains(".disabled(!store.canChangePlaybackView || (isNativeStudy ? target == nil : cue == nil))"))
        XCTAssertTrue(control.contains("PlaybackBallActionNavigation.jump(direction, source: nativeActionSource, in: store)"))
        XCTAssertTrue(control.contains("jump(to: cue)"), "Legacy scenarios retain their teaching cues")
        XCTAssertTrue(control.contains("minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        XCTAssertTrue(control.contains("minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        XCTAssertTrue(control.contains(".help("))
        XCTAssertTrue(control.contains(".accessibilityLabel(label)"))
    }

    func testMarkListChecksOwnershipBeforeChangingSelectionOrVisibility() throws {
        let source = try immersiveSource()
        let events = try slice(source, after: "private var annotationEventStrip:",
            before: "private func selectedAnnotationInspector(")
        let admission = try XCTUnwrap(events.range(of: "guard store.canChangePlaybackView, jump(to: mark) else { return }")?.lowerBound)
        for effect in ["selectedAnnotationID = mark.id", "showsEventStrip = false",
                       "showsPlaybackAnnotations = true"] {
            XCTAssertLessThan(admission, try XCTUnwrap(events.range(of: effect)?.lowerBound))
        }
    }

    func testCueMarkStepAndAccessibilityCallbacksRejectCompetingTimelineActions() throws {
        let source = try immersiveSource()
        for (start, end) in [
            ("private func jump(to cue: CueMoment)", "private func jump(to mark: CoachMark)"),
            ("private func nudgeTimeline(by delta:", "private func openAdjacentPlayerPOV("),
            ("private func adjustTimelineForAccessibility(direction:", "private var shapeFocusStatusDeck:")
        ] {
            let callback = try slice(source, after: start, before: end)
            assertAdmissionBefore("store.setPlaying(false", in: callback)
        }
        let mark = try slice(source, after: "private func jump(to mark: CoachMark)",
                             before: "private func nudgeTimeline(by delta:")
        XCTAssertTrue(mark.contains("guard store.canChangePlaybackView else { return false }"))
        XCTAssertTrue(mark.contains("PlaybackAnnotationEventNavigation.jump(to: mark.id, in: store)"))

        let step = try slice(source, after: "private func timelineStepChoice(", before: "private func playbackRateChoice(")
        XCTAssertTrue(step.contains(".disabled(!store.canChangePlaybackView)"))
        XCTAssertTrue(step.contains(".buttonRepeatBehavior(.enabled)"), "Stepping should still repeat after the scrub ends")
    }

    func testOwningRailRetainsItsSeparateUpdateAndCompletionGate() throws {
        let source = try immersiveSource()
        let policy = try slice(source, after: "private var timelineControlsAreDisabled: Bool", before: "private var rateControlsAreDisabled:")
        XCTAssertTrue(policy.contains("store.isDrawing || store.hasActiveCoachMarkGeometryPreview"))
        XCTAssertTrue(policy.contains("store.hasActiveTimelineScrub"))
        XCTAssertTrue(policy.contains("timelineScrubController.storeScrubID != store.activeTimelineScrubID"),
                      "Only a foreign timeline owner disables the rail during scrubbing")
        XCTAssertFalse(policy.contains("canChangePlaybackView"))
        let update = try slice(source, after: "private func updateTimelineScrub(", before: "private func finishTimelineScrub(")
        let finish = try slice(source, after: "private func finishTimelineScrub(", before: "private func cancelInterruptedTimelineScrub()")
        XCTAssertTrue(update.contains("guard !timelineControlsAreDisabled else"))
        XCTAssertTrue(finish.contains("guard !timelineControlsAreDisabled else"))
        XCTAssertTrue(update.contains("timelineScrubController.preview(in: store"))
        XCTAssertTrue(finish.contains("timelineScrubController.finish(in: store"))
        XCTAssertFalse(finish.contains("updateTimelineScrub("), "End callbacks cannot start a fresh scrub")
    }

    func testStoreKeepsTheOwnedPreviewWhenACompetingCueOrMarkJumpIsAttempted() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 12))
        let cue = try XCTUnwrap(store.selectedScenario.moments.last)
        let mark = try XCTUnwrap(store.marks.last)
        XCTAssertFalse(store.canChangePlaybackView)

        for competingTime in [cue.time, mark.revealTime] {
            // These were the old UI callbacks: Store correctly rejects both,
            // so UI selection/visibility must be gated before reaching them.
            store.setPlaying(false, broadcast: false)
            store.seek(to: competingTime, broadcast: false)
            XCTAssertEqual(store.playhead, 12)
            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.statusMessage, "Finish or cancel the timeline scrub first")
        }

        XCTAssertTrue(store.previewTimelineScrub(to: 13))
        XCTAssertTrue(store.commitTimelineScrub(to: 13))
        XCTAssertEqual(store.playhead, 13)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(store.canChangePlaybackView)
    }

    func testStoreNormalSeeksRemainPausedAtTheirChosenMoment() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let cue = try XCTUnwrap(store.selectedScenario.moments.last)
        let mark = try XCTUnwrap(store.marks.first)
        for selectedTime in [cue.time, mark.revealTime] {
            store.setPlaying(true, broadcast: false)
            XCTAssertTrue(store.canChangePlaybackView)
            store.setPlaying(false, broadcast: false)
            store.seek(to: selectedTime, broadcast: false)
            XCTAssertEqual(store.playhead, selectedTime)
            XCTAssertFalse(store.isPlaying)
            XCTAssertFalse(store.hasActiveTimelineScrub)
        }
    }

    private func assertAdmissionBefore(
        _ sideEffect: String,
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let admission = source.range(of: "guard store.canChangePlaybackView else { return }")?.lowerBound
        let effect = source.range(of: sideEffect)?.lowerBound
        XCTAssertNotNil(admission, "Discrete actions must reject the owned scrub before side effects", file: file, line: line)
        XCTAssertNotNil(effect, file: file, line: line)
        if let admission, let effect {
            XCTAssertLessThan(admission, effect, file: file, line: line)
        }
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
