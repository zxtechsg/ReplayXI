import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTrackingKeyframeAvailabilityTests: XCTestCase {
    func testTrackingRosterIsReplacedByLiveEditor() throws {
        let source = try immersiveSource()
        XCTAssertFalse(source.contains("private func annotationTrackingPlayerButton("))
        let route = try slice(source, after: "case .annotationTracking(let markID):",
            before: "case .annotationActions(let markID):")
        XCTAssertTrue(route.contains("selectedAnnotationInspector(mark)"))
        XCTAssertFalse(route.contains("freezeCoachMarkKeyframes"))
    }

    func testKeyedMarkFollowsEitherTeamWithoutLosingEarlierPoses() throws {
        for team in [FootballTeam.home, .away] {
            let (store, mark) = try keyedFixture()
            let player = try XCTUnwrap(store.selectedScenario.players.first { $0.team == team })
            XCTAssertTrue(AnnotationTrackingPolicy.canSetTracking(mark, canChangePlaybackView: true))
            XCTAssertFalse(AnnotationTrackingPolicy.canSetTracking(mark, canChangePlaybackView: false))
            let displayed = store.presentedCoachMarkGeometry(mark, at: store.playhead)
            XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: player.id))
            let tracked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
            XCTAssertEqual(tracked.keyframes?.map(\.time), [2, 3, 4])
            XCTAssertEqual(tracked.keyframes?.first, mark.keyframes?.first)
            XCTAssertEqual(tracked.keyframes?.last, mark.keyframes?.last)
            XCTAssertEqual(tracked.sampled(at: 3).startTrackAnchor?.playerID, player.id)
            XCTAssertEqual(tracked.sampled(at: 3).endTrackAnchor?.playerID, player.id)
            XCTAssertEqual(store.presentedCoachMarkGeometry(tracked, at: 3).start, displayed.start)
            XCTAssertEqual(store.playhead, 3)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
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

    func testOldTimingRouteOpensLiveInspectorWithoutMutatingKeys() throws {
        let source = try immersiveSource()
        let route = try slice(source, after: "case .annotationDuration(let markID):",
            before: "case .annotationGeometry(let markID):")
        XCTAssertTrue(route.contains("selectedAnnotationInspector(mark)"))
        XCTAssertFalse(route.contains("freezeCoachMarkKeyframes"))
        XCTAssertFalse(route.contains("AnnotationTimingEditor("))
        XCTAssertFalse(source.contains("private func annotationDurationShelf("))
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
