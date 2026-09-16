import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationMoveAvailabilityTests: XCTestCase {
    func testHeldTimelineDisablesMoveWithoutChangingScrubCommitOrCancel() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.setPlaying(true, broadcast: false)
            XCTAssertTrue(store.beginTimelineScrub())
            XCTAssertTrue(store.previewTimelineScrub(to: 12))

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.playhead, 12)

            if commits {
                XCTAssertTrue(store.commitTimelineScrub(to: 14))
                XCTAssertEqual(store.playhead, 14)
            } else {
                store.cancelTimelineScrub()
                XCTAssertEqual(store.playhead, 5)
                store.seek(to: 12, broadcast: false)
            }
            XCTAssertTrue(store.isPlaying)
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testHeldWorldHandleDisablesMoveWithoutChangingItsPreviewOrCompletion() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.seek(to: 12, broadcast: false)
            let end = PitchPoint(x: mark.end.x + 0.5, z: mark.end.z)
            XCTAssertTrue(store.updateCoachMarkGeometry(
                id: mark.id, start: mark.start, end: end, broadcast: false))

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)

            if commits {
                XCTAssertTrue(store.commitCoachMarkGeometryPreview(
                    id: mark.id, start: mark.start, end: end))
                XCTAssertEqual(try currentMark(mark.id, in: store).end, end)
            } else {
                XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
                XCTAssertEqual(try currentMark(mark.id, in: store), mark)
            }
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testHeldJoystickDisablesMoveAndKeepsTheExactEndpointOwner() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.seek(to: 12, broadcast: false)
            let gestureID = UUID()
            let movement = PitchPoint(x: 0.5, z: -0.25)
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: gestureID, cumulativeDelta: movement))
            let owner = CoachMarkEndpointPreviewOwner(markID: mark.id, endpoint: .end)

            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
            assertStoreRejectsMove(mark, in: store)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)

            if commits {
                XCTAssertEqual(store.commitCoachMarkEndpointPreview(
                    id: mark.id, gestureID: gestureID), movement)
            } else {
                XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
                XCTAssertEqual(try currentMark(mark.id, in: store), mark)
            }
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))
        }
    }

    func testOrdinaryReplayAndShapeMovesStillRetimeOnceAndUndoExactly() throws {
        for scenarioID in ["real-world-match-replay", "triangle-lock"] {
            let (store, mark) = try makeMark(scenarioID: scenarioID)
            store.seek(to: 12, broadcast: false)
            let baseline = store.marks
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: store.playhead, in: store))

            store.setPlaying(false, broadcast: false)
            XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: store.playhead))

            let moved = try currentMark(mark.id, in: store)
            XCTAssertEqual(moved.revealTime, 12)
            XCTAssertEqual(moved.hideTime, 20)
            XCTAssertEqual(moved.start, mark.start)
            XCTAssertEqual(moved.end, mark.end)
            XCTAssertEqual(moved.startTrackAnchor, mark.startTrackAnchor)
            XCTAssertEqual(moved.endTrackAnchor, mark.endTrackAnchor)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, baseline)
            XCTAssertEqual(store.playhead, 12)
        }
    }

    func testOriginalTimeDifferenceAndWindowBoundsRemainUnchanged() throws {
        let (store, mark) = try makeMark()
        for time: TimeInterval in [-1, 5, 5.04, 24.01, 31, 32, 33, .nan, .infinity] {
            XCTAssertFalse(PlaybackAnnotationMovePolicy.canMove(mark, to: time, in: store), "\(time)")
        }
        for time: TimeInterval in [0, 5.06, 12, 24] {
            XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(mark, to: time, in: store), "\(time)")
        }
        XCTAssertTrue(store.setCoachMarkDuration(id: mark.id, duration: nil))
        let throughEnd = try currentMark(mark.id, in: store)
        XCTAssertTrue(PlaybackAnnotationMovePolicy.canMove(throughEnd, to: 32, in: store))
    }

    func testVisibleMoveUsesTheLivePolicyAndGuardsItsCallbackAndHint() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let lower = try XCTUnwrap(source.range(of: "Label(\"SCRUB ABOVE\"")?.lowerBound)
        let upper = try XCTUnwrap(source.range(of: "private func annotationGeometryButton(",
            range: lower..<source.endIndex)?.lowerBound)
        let move = String(source[lower..<upper])
        XCTAssertTrue(source.contains("PlaybackAnnotationMovePolicy.canMove(mark, to: time, in: store)"))
        XCTAssertTrue(move.contains(".disabled(!canMoveAnnotation(mark, to: store.playhead))"))
        let gate = move.range(of: "guard canMoveAnnotation(mark, to: store.playhead) else { return }")?.lowerBound
        let pause = try XCTUnwrap(move.range(of: "store.setPlaying(false, broadcast: false)")?.lowerBound)
        XCTAssertNotNil(gate, "A delayed callback must recheck availability before pausing")
        if let gate { XCTAssertLessThan(gate, pause) }
        let hintStart = try XCTUnwrap(move.range(of: ".accessibilityHint(")?.lowerBound)
        let hint = move[hintStart...]
        XCTAssertTrue(hint.contains("store.canChangePlaybackView"))
        XCTAssertTrue(hint.contains("Finish or cancel the current gesture first"))
    }

    private func assertStoreRejectsMove(_ mark: CoachMark, in store: ReplayStore,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let marks = store.marks
        let snapshot = store.makeSnapshot()
        let history = store.annotationUndoTitle
        XCTAssertFalse(store.canChangePlaybackView, file: file, line: line)
        // The current visible callback requests this pause before its retime.
        store.setPlaying(false, broadcast: false)
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: store.playhead), file: file, line: line)
        XCTAssertEqual(store.marks, marks, file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(store.annotationUndoTitle, history, file: file, line: line)
    }

    private func makeMark(scenarioID: String = "real-world-match-replay") throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: scenarioID)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        XCTAssertFalse(store.isDrawing)
        XCTAssertEqual(mark.hideTime, 13)
        return (store, mark)
    }

    private func currentMark(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }
}
