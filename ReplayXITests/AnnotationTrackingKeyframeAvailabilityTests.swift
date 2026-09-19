import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTrackingKeyframeAvailabilityTests: XCTestCase {
    func testKeyframedFollowControlsUseAKeyAwareGate() throws {
        let source = try immersiveSource()
        let button = try slice(source, after: "private func annotationTrackingPlayerButton(",
                               before: "private func annotationTrackingPlayerID(")
        XCTAssertTrue(button.contains(".disabled(!annotationTrackingIsEnabled(mark))"),
                      "Keyframed marks must not expose shirts that Store refuses to follow")
        let callback = try slice(source, after: "private func setAnnotationTracking(",
                                 before: "private func annotationLabelShelf(")
        XCTAssertTrue(callback.contains("guard annotationTrackingIsEnabled(mark) else { return }"))
    }

    func testKeyedMarkRequiresExplicitFreezeBeforeFollowingEitherTeam() throws {
        for team in [FootballTeam.home, .away] {
            let (store, mark) = try keyedFixture()
            let player = try XCTUnwrap(store.selectedScenario.players.first { $0.team == team })
            let original = store.marks
            XCTAssertTrue(store.canChangePlaybackView, "The existing UI gate is true for this rejected action")
            XCTAssertFalse(AnnotationTrackingPolicy.canSetTracking(mark, canChangePlaybackView: store.canChangePlaybackView))
            XCTAssertFalse(store.setCoachMarkTracking(id: mark.id, playerID: player.id))
            XCTAssertEqual(store.marks, original)
            XCTAssertTrue(store.freezeCoachMarkKeyframes(id: mark.id))
            let frozen = try XCTUnwrap(store.marks.first { $0.id == mark.id })
            XCTAssertFalse(frozen.hasKeyframes)
            XCTAssertTrue(AnnotationTrackingPolicy.canSetTracking(frozen, canChangePlaybackView: store.canChangePlaybackView))
            XCTAssertFalse(AnnotationTrackingPolicy.canSetTracking(frozen, canChangePlaybackView: false))
            XCTAssertEqual(frozen.start, mark.sampled(at: store.playhead).start)
            XCTAssertEqual(frozen.end, mark.sampled(at: store.playhead).end)
            XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: player.id))
            let tracked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
            let displayed = store.presentedCoachMarkGeometry(tracked, at: store.playhead)
            XCTAssertEqual(displayed.start.x, frozen.start.x, accuracy: 0.001)
            XCTAssertEqual(displayed.start.z, frozen.start.z, accuracy: 0.001)
            XCTAssertEqual(displayed.end.x, frozen.end.x, accuracy: 0.001)
            XCTAssertEqual(displayed.end.z, frozen.end.z, accuracy: 0.001)
            XCTAssertEqual(store.playhead, 3)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, frozen)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, original, "Freeze and Follow remain separate explicit Undo actions")
        }
    }

    func testKeyframedStatusAndAccessibilityDoNotClaimTheMarkIsFixed() throws {
        let (_, original) = try keyedFixture()
        XCTAssertEqual(AnnotationTrackingPolicy.keyframeStatus(original), "2 POSITION KEYS")
        XCTAssertEqual(AnnotationTrackingPolicy.keyframeAccessibilityValue(original),
                       "2 saved positions, controlled by timestamps")
        XCTAssertEqual(AnnotationTrackingPolicy.playerHint(original, canChangePlaybackView: true),
                       AnnotationTrackingPolicy.keyframeHint)
        var single = original
        single.keyframes = [try XCTUnwrap(original.keyframes?.first)]
        XCTAssertEqual(AnnotationTrackingPolicy.keyframeStatus(single), "1 POSITION KEY")
        XCTAssertEqual(AnnotationTrackingPolicy.keyframeAccessibilityValue(single),
                       "1 saved position, controlled by timestamps")
        var fixed = original
        fixed.keyframes = nil
        XCTAssertNil(AnnotationTrackingPolicy.keyframeStatus(fixed))
        XCTAssertNil(AnnotationTrackingPolicy.keyframeAccessibilityValue(fixed))
        XCTAssertEqual(AnnotationTrackingPolicy.playerHint(fixed, canChangePlaybackView: false),
                       "Finish or cancel the current gesture first")
    }

    func testKeyframedShelfLinksToExistingTimingWithoutMutationOrSelectionLoss() throws {
        let source = try immersiveSource()
        let shelf = try slice(source, after: "private func annotationTrackingShelf(",
                              before: "private func annotationTrackingTeamRow(")
        let notice = try slice(shelf, after: "AnnotationTrackingKeyframeNotice(",
                               before: "} else {")
        XCTAssertTrue(notice.contains("toggleInlinePanel(.annotationDuration(mark.id))"))
        XCTAssertTrue(notice.contains("guard store.canChangePlaybackView else { return }"))
        XCTAssertFalse(notice.contains("selectedAnnotationID ="))
        XCTAssertFalse(shelf.contains("freezeCoachMarkKeyframes"), "Opening Follow must never erase position keys")
        XCTAssertTrue(shelf.contains("if mark.hasKeyframes {"))
        XCTAssertTrue(shelf.contains("} else {\n                    annotationTrackingTeamRow("))
        let status = try slice(source, after: "private func annotationTrackingSummary(",
                               before: "private func setAnnotationTracking(")
        XCTAssertTrue(status.contains("AnnotationTrackingPolicy.keyframeStatus(mark)"))
        let voiceOver = try slice(source, after: "private func annotationTrackingAccessibilityValue(",
                                  before: "private func nudgeAnnotation(")
        XCTAssertTrue(voiceOver.contains("AnnotationTrackingPolicy.keyframeAccessibilityValue(mark)"))
    }

    func testOrdinaryTrackingRemainsAvailableButPlayerLabelsCannotTrack() throws {
        let (store, keyed) = try keyedFixture()
        XCTAssertTrue(store.freezeCoachMarkKeyframes(id: keyed.id))
        let mark = try XCTUnwrap(store.marks.first { $0.id == keyed.id })
        XCTAssertTrue(AnnotationTrackingPolicy.canSetTracking(mark, canChangePlaybackView: true))
        let player = try XCTUnwrap(store.selectedScenario.homePlayers.first)
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: player.id))
        let tracked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertTrue(AnnotationTrackingPolicy.canSetTracking(tracked, canChangePlaybackView: true))
        XCTAssertFalse(AnnotationTrackingPolicy.canSetTracking(tracked, canChangePlaybackView: false))
        let label = CoachMark(kind: .playerLabel, start: mark.start, end: mark.end,
                              label: "Runner", revealTime: 0, author: "Coach", playerID: player.id)
        XCTAssertFalse(AnnotationTrackingPolicy.canSetTracking(label, canChangePlaybackView: true))
    }

    private func keyedFixture() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        if created.followsPlayerTracks { XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil)) }
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        store.seek(to: 4)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id, start: .init(x: -18, z: -20),
                                                   end: .init(x: -14, z: -14)))
        store.seek(to: 3)
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(mark.keyframes?.count, 2)
        return (store, mark)
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after: String, before: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: after)?.lowerBound)
        let end = try XCTUnwrap(source[start...].range(of: before)?.lowerBound)
        return String(source[start..<end])
    }
}
