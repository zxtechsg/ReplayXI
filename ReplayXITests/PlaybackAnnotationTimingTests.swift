import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationTimingTests: XCTestCase {
    private func draw(_ store: ReplayStore, kind: CoachMarkKind = .pass) throws -> CoachMark {
        store.beginDrawing(kind)
        _ = store.registerPitchTap(PitchPoint(x: -3, z: 2))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 5, z: 9)))
    }

    func testNewMarksNearReplayEndStayVisibleOnTheLastPausedFrame() throws {
        for kind in CoachMarkKind.allCases {
            let store = ReplayStore()
            let end = store.selectedScenario.duration
            store.seek(to: end - 0.25)
            let mark: CoachMark
            if kind == .playerLabel {
                mark = try XCTUnwrap(store.labelPlayer(store.localPerspectiveID))
            } else {
                mark = try draw(store, kind: kind)
            }
            XCTAssertNil(mark.hideTime, "A new tail annotation should use To end, not an off-clip timestamp")
            XCTAssertTrue(mark.isVisible(at: end))
            XCTAssertTrue(store.flushReviewAutosave())
            XCTAssertEqual(store.autosavedReview?.state.marks.last, mark)
        }
        let store = ReplayStore()
        store.seek(to: store.selectedScenario.duration)
        store.addPresetMark()
        let mark = try XCTUnwrap(store.marks.last)
        XCTAssertNil(mark.hideTime)
        XCTAssertTrue(mark.isVisible(at: store.selectedScenario.duration))
    }

    func testDefaultWindowIsEightSecondsUntilItReachesTheEnd() throws {
        let store = ReplayStore()
        store.seek(to: 5)
        XCTAssertEqual(try draw(store).hideTime, 13)
        store.seek(to: store.selectedScenario.duration - 8)
        XCTAssertNil(try draw(store).hideTime)
    }

    func testExplicitDurationAndRetimeCannotCreateOffClipWindows() throws {
        let store = ReplayStore()
        store.seek(to: 8)
        let mark = try draw(store)
        let before = store.marks
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: store.selectedScenario.duration - 1))
        XCTAssertEqual(store.marks, before)
        XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: 12))

        store.seek(to: store.selectedScenario.duration - 2)
        let tail = try draw(store)
        let tailBefore = store.marks
        XCTAssertFalse(store.setCoachMarkDuration(id: tail.id, duration: 3))
        XCTAssertEqual(store.marks, tailBefore)
        XCTAssertTrue(store.setCoachMarkDuration(id: tail.id, duration: 1))
        XCTAssertEqual(store.marks.last?.hideTime, store.selectedScenario.duration - 1)
        XCTAssertTrue(store.setCoachMarkDuration(id: tail.id, duration: nil))
        XCTAssertTrue(store.retimeCoachMark(id: tail.id, to: store.selectedScenario.duration))
        XCTAssertNil(store.marks.last?.hideTime)
    }

    func testUnfinishedDrawingOwnsTransportThroughEveryStoreRoute() throws {
        let store = ReplayStore()
        store.seek(to: 8)
        store.beginDrawing(.run)
        let start = PitchPoint(x: 2, z: 3)
        _ = store.registerPitchTap(start)
        store.togglePlayback()
        XCTAssertFalse(store.isPlaying)
        store.setPlaying(true)
        XCTAssertFalse(store.isPlaying)
        store.seek(to: 17)
        store.skip(by: 3)
        store.setPlaybackRate(4)
        XCTAssertEqual(store.playhead, 8)
        XCTAssertEqual(store.playbackRate, 1)
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertTrue(store.isDrawing)
        store.setPlaying(false)
        store.cancelDrawing()
        store.seek(to: 17)
        store.setPlaybackRate(2)
        store.setPlaying(true)
        XCTAssertEqual(store.playhead, 17)
        XCTAssertEqual(store.playbackRate, 2)
        XCTAssertTrue(store.isPlaying)
    }

    func testPresetMarksRemainReadableAtEveryPitchCorner() throws {
        for point in [PitchPoint(x: 34, z: 52.5), PitchPoint(x: -34, z: 52.5),
                      PitchPoint(x: 34, z: -52.5), PitchPoint(x: -34, z: -52.5),
                      PitchPoint(x: 33.9, z: 52.4), .zero] {
            for kind in CoachMarkKind.allCases where kind != .playerLabel {
                let store = try cornerStore(at: point)
                store.selectedTool = kind
                store.addPresetMark()
                let mark = try XCTUnwrap(store.marks.last)
                XCTAssertGreaterThan(ReplayGeometry.distance(mark.start, mark.end), 11)
                XCTAssertTrue(CoachMarkGeometryPolicy.accepts(kind: kind, start: mark.start, end: mark.end))
                XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: store.selectedScenario))
                XCTAssertTrue(store.flushReviewAutosave())
                XCTAssertTrue(store.undoAnnotationEdit())
                XCTAssertTrue(store.marks.isEmpty)
            }
        }
    }

    func testOlderSavedOffClipWindowsRemainReadableAndCanBeCorrected() throws {
        let store = ReplayStore()
        let end = store.selectedScenario.duration
        let old = CoachMark(kind: .run, start: PitchPoint(x: -2, z: 3), end: PitchPoint(x: 4, z: 8),
                            label: "Older review", revealTime: end - 1, hideTime: end + 7)
        store.marks.append(old)
        XCTAssertTrue(ReplayStore.isValidReviewMark(old, for: store.selectedScenario))
        XCTAssertTrue(store.saveReview(named: "Legacy tail"))
        let review = try XCTUnwrap(store.savedReviews.first)
        XCTAssertTrue(store.restoreReview(review))
        XCTAssertEqual(store.marks.last, old)
        XCTAssertTrue(store.updateCoachMarkLabel(id: old.id, label: "Still editable"))
        XCTAssertFalse(store.setCoachMarkDuration(id: old.id, duration: 3))
        XCTAssertTrue(store.setCoachMarkDuration(id: old.id, duration: nil))
        XCTAssertNil(store.marks.last?.hideTime)
        XCTAssertTrue(store.marks.last?.isVisible(at: end) ?? false)
        XCTAssertTrue(store.flushReviewAutosave())
    }

    func testInvalidAnnotationTimesAndTimingPayloadsCannotEnterNewMarks() {
        for time in [Double.nan, .infinity, -.infinity, -1, 33] {
            let store = ReplayStore()
            let before = store.marks
            store.playhead = time
            store.beginDrawing(.run)
            XCTAssertFalse(store.isDrawing)
            XCTAssertNil(store.labelPlayer(store.localPerspectiveID))
            store.addPresetMark()
            XCTAssertEqual(store.marks, before)
        }
        for duration in [Double.nan, .infinity, -.infinity, -1, 0, 31] {
            XCTAssertFalse(CoachMarkTimingPolicy.windowFits(revealTime: 0, displayDuration: duration, replayDuration: 32))
        }
        XCTAssertTrue(CoachMarkTimingPolicy.windowFits(revealTime: 32, displayDuration: nil, replayDuration: 32))
        XCTAssertFalse(CoachMarkTimingPolicy.windowFits(revealTime: 32, displayDuration: 0.000_000_1, replayDuration: 32))
        XCTAssertFalse(CoachMarkTimingPolicy.windowFits(revealTime: 33, displayDuration: nil, replayDuration: 32))
        XCTAssertFalse(CoachMarkTimingPolicy.windowFits(revealTime: 0, displayDuration: nil, replayDuration: .nan))
        XCTAssertTrue(CoachMarkTimingPolicy.windowFits(revealTime: 0.2, displayDuration: 0.1, replayDuration: 0.3))
    }

    private func cornerStore(at point: PitchPoint) throws -> ReplayStore {
        let base = try XCTUnwrap(DemoScenarios.all.first)
        let source = try XCTUnwrap(base.players.first)
        let player = PlayerTrack(id: source.id, displayName: source.displayName, role: source.role,
            shirtNumber: source.shirtNumber, team: source.team, isGoalkeeper: false,
            keyframes: [MotionKeyframe(time: 0, position: point, facingDegrees: 0),
                        MotionKeyframe(time: base.duration, position: point, facingDegrees: 0)])
        let scenario = ReplayScenario(id: "corner-test", kind: base.kind, title: "Corner test",
            strapline: "Test", matchContext: "Synthetic", objective: "Test", coachPrompt: "Test",
            proofPoint: "Test", duration: base.duration, defaultViewMode: .tacticalTable,
            defaultPerspectiveID: player.id, featuredPerspectiveIDs: [player.id], players: [player],
            ball: base.ball, moments: [], coachMarks: [], formationTargets: [])
        return ReplayStore(scenarios: [scenario])
    }
}
